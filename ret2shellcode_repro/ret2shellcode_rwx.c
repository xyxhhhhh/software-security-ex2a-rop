#define _GNU_SOURCE

#include <sys/mman.h>

/* The course sample assumes buf2 is executable.  Modern kernels map .bss RW. */
__attribute__((constructor)) static void make_buf2_rwx(void) {
    mprotect((void *)0x0804a000, 0x1000,
             PROT_READ | PROT_WRITE | PROT_EXEC);
}
