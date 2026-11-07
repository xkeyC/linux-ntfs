#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Run a list of scenarios in parallel.
#
# usage: matrix.sh KERNEL INITRD IMAGEDIR OUTDIR MATRIXFILE [JOBS]
# MATRIXFILE: one "NTFSMOD SCENARIO SIGNAL" per line; see matrix-example.txt.
# Each line boots its own VM (4 vCPUs, 3 GiB); reads are throttled, so the VMs
# mostly wait. Prints the summaries sorted; also writes OUTDIR/summary.txt.
set -eu
[ $# -ge 5 ] || { sed -n '3,8p' "$0"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
kernel=$1 initrd=$2 imgdir=$3 out=$4 matrix=$5 jobs=${6:-4}
mkdir -p "$out"
grep -vE '^\s*(#|$)' "$matrix" |
	xargs -P "$jobs" -L1 "$here/run.sh" "$kernel" "$initrd" "$imgdir" "$out" |
	sort > "$out/summary.txt"
cat "$out/summary.txt"
