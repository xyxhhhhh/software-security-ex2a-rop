#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MARKER="RET2LIBC1_OK"

output="$(printf 'echo %s\nexit\n' "$MARKER" | timeout 30s python3 "$SCRIPT_DIR/exploit.py" 2>&1)" || {
    status=$?
    printf '%s\n' "$output"
    printf 'ret2libc1 failed (exit %s)\n' "$status" >&2
    exit "$status"
}
printf '%s\n' "$output"
grep -Fq "$MARKER" <<<"$output" || {
    printf 'ret2libc1 did not print %s\n' "$MARKER" >&2
    exit 1
}
