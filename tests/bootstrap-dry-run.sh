#!/bin/sh
set -eu
output=$(BOOTSTRAP_DRY_RUN=1 sh ./bootstrap.sh 2>&1)
printf '%s\n' "$output" | grep -F 'Detected x86_64-linux' >/dev/null
printf '%s\n' "$output" | grep -F 'Preserving temporary bootstrap files:' >/dev/null
