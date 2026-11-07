#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Create the template images: an empty 40 GiB NTFS volume (sparse) and three
# filled ones. Filling runs in the guest through the ntfs driver.
#
# usage: mkimages.sh KERNEL INITRD NTFSMOD DIR
# Creates DIR/tpl-{empty,spread,bigfile,dir}.img. Needs mkntfs.
set -eu
[ $# -eq 4 ] || { sed -n '3,7p' "$0"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
kernel=$1 initrd=$2 mod=$3 dir=$4
mkdir -p "$dir"
rm -f "$dir/tpl-empty.img"
truncate -s 40G "$dir/tpl-empty.img"
mkntfs -F -Q -q "$dir/tpl-empty.img" 2>/dev/null
for set in spread bigfile dir; do
	cp --sparse=always "$dir/tpl-empty.img" "$dir/tpl-$set.img"
	echo "filling tpl-$set.img"
	THROTTLE=0 "$here/qemu.sh" "$kernel" "$initrd" "$dir/tpl-$set.img" "$mod" "prep-$set" KILL 1
done
