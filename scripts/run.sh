#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Run one scenario on a fresh copy of its template, then check the image.
#
# usage: run.sh KERNEL INITRD IMAGEDIR OUTDIR NTFSMOD SCENARIO SIGNAL [RUNS]
# Writes OUTDIR/SCENARIO-NTFSMOD-SIGNAL.{log,fsck} and prints a one-line summary.
# Needs ntfsck (ntfsprogs-plus) for the check.
set -eu
[ $# -ge 7 ] || { sed -n '3,7p' "$0"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
kernel=$1 initrd=$2 imgdir=$3 out=$4 mod=$5 scen=$6 sig=$7 runs=${8:-20}
case $scen in
spread|eio) tpl=spread ;;
bigfile) tpl=bigfile ;;
dir-rm|dir-create|lookup) tpl=dir ;;
falloc|write) tpl=empty ;;
*) echo "unknown scenario $scen"; exit 1 ;;
esac
mkdir -p "$out"
id=$scen-$mod-$sig
img=$imgdir/run-$id.img
cp --reflink=auto --sparse=always "$imgdir/tpl-$tpl.img" "$img"
th=1
[ "$scen" = eio ] && th=0
THROTTLE=$th "$here/qemu.sh" "$kernel" "$initrd" "$img" "$mod" "$scen" "$sig" "$runs" > "$out/$id.log" 2>&1 || true
ntfsck -n "$img" 2>&1 | sed "s|$img|IMAGE|g" > "$out/$id.fsck" || true
rm -f "$img"
echo "$id: $(grep -a 'RESULT\|INSMOD FAILED\|MOUNT FAILED\|DMSETUP FAILED' "$out/$id.log" | sed 's/.*ro_after/ro_after/') | ntfsck: $(tail -1 "$out/$id.fsck")"
