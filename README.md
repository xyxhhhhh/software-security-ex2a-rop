# 软件与系统安全 · 实验 2A（ROP）

本仓库整理六道基础 ROP 练习与一道进阶 `ret2dlresolve` 复现，包含每题 exploit、说明、启动脚本、配套教学目标二进制/可用源码、实验报告和本机验证记录。

## 题目

- `ret2text_repro/`：跳转到程序已有代码
- `ret2shellcode_repro/`：写入并执行 shellcode
- `ret2syscall_repro/`：ROP 设置寄存器后触发 `int 0x80`
- `ret2libc1_repro/`：调用已有 `system` 和 `/bin/sh`
- `ret2libc2_repro/`：写入 `/bin/sh` 后调用 `system`
- `ret2libc3_repro/`：GOT 泄漏、计算 libc 基址并调用 `system`
- `ret2dlresolve_repro/`：伪造动态重定位数据并利用 PLT0 解析 `system`

题目原理、保护配置、偏移和 payload 说明分别见各题 README。课程 DOCX 报告保存在作者本机桌面，不随本仓库公开。`实验2A_报告证据/` 保存七题复现输出、checksec/GDB 操作记录和 cyclic 输入文件。

## 环境

复现记录来自 Ubuntu 20.04 x86_64，目标为 32 位 i386 ELF。需要 Python 3、pwntools、GDB、GCC multilib 和 32 位运行库。Ubuntu/Debian 可安装：

```bash
sudo apt install gcc-multilib libc6-dev-i386 gdb
python3 -m pip install pwntools
```

从仓库根目录执行：

```bash
./ret2text_repro/run.sh
./ret2shellcode_repro/run.sh
./ret2syscall_repro/run.sh
./ret2libc1_repro/run.sh
./ret2libc2_repro/run.sh
./ret2libc3_repro/run.sh
./ret2dlresolve_repro/run.sh
```

`ret2shellcode` 教学样例需要 `LD_PRELOAD` 辅助库临时将 `.bss` 页设为 RWX；相应源码和限制已在说明、报告中披露。所有利用仅针对仓库内的本地教学样例。

## 来源与许可

基础样例来自 [ctf-wiki/ctf-challenges](https://github.com/ctf-wiki/ctf-challenges) 的相应题目目录；`ret2dlresolve` 样例为 XDCTF2015 pwn200。随附目标程序和源码保留上游版权及许可，使用者应遵守上游项目许可。本仓库新增实验脚本和说明用于课程学习。
