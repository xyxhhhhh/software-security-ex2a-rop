#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MARKER="RET2SHELLCODE_OK"
HELPER="/tmp/ret2shellcode_rwx.so"

command -v gcc >/dev/null || { printf 'gcc is required\n' >&2; exit 127; }
gcc -m32 -shared -fPIC "$SCRIPT_DIR/ret2shellcode_rwx.c" -o "$HELPER"

output="$(timeout 30s python3 "$SCRIPT_DIR/exploit.py" 2>&1)" || {
    status=$?
    printf '%s\n' "$output"
    printf 'ret2shellcode failed (exit %s)\n' "$status" >&2
    exit "$status"
}
printf '%s\n' "$output"
grep -Fq "$MARKER" <<<"$output" || {
    printf 'ret2shellcode did not print %s\n' "$MARKER" >&2
    exit 1
}
