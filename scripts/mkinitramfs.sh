#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Build the test initramfs.
#
# usage: mkinitramfs.sh -o initrd.gz -b /path/to/static/busybox \
#            -m NAME=/path/to/ntfs.ko [-m NAME2=/path/to/other/ntfs.ko ...] \
#            [-d /path/to/dmsetup] [-e /dir/with/extra/modules] [-x /path/to/static/tool]
#
#  -m  ntfs modules to test; the guest loads /lib/ntfs-NAME.ko for ntfsmod=NAME
#  -d  dmsetup binary, only needed for the eio scenario; its shared libraries
#      (as reported by ldd) are copied too
#  -e  directory with modules the kernel needs before ntfs (e.g. virtio_ring,
#      virtio, virtio_pci, virtio_blk on a distro kernel) plus a file "order"
#      that lists their names, one per line, in load order
#  -x  extra static program to put in /bin, e.g. tools/ntfs-stream for the
#      stream scenario (repeatable)
set -eu
out='' busybox='' dmsetup='' extra=''
mods=
tools=
while getopts o:b:m:d:e:x: opt; do
	case $opt in
	o) out=$OPTARG ;;
	b) busybox=$OPTARG ;;
	m) mods="$mods $OPTARG" ;;
	d) dmsetup=$OPTARG ;;
	e) extra=$OPTARG ;;
	x) tools="$tools $OPTARG" ;;
	*) sed -n '3,16p' "$0"; exit 1 ;;
	esac
done
[ -n "$out" ] && [ -n "$busybox" ] && [ -n "$mods" ] || { sed -n '3,16p' "$0"; exit 1; }

here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/sbin" "$root/lib" "$root/proc" "$root/sys" "$root/dev" "$root/mnt"
cp "$busybox" "$root/bin/busybox"
for a in $("$root/bin/busybox" --list); do [ -e "$root/bin/$a" ] || ln -s busybox "$root/bin/$a"; done
cp "$here/guest-init" "$root/init"
chmod +x "$root/init"
for m in $mods; do
	cp "${m#*=}" "$root/lib/ntfs-${m%%=*}.ko"
done
for t in $tools; do
	cp "$t" "$root/bin/"
done
if [ -n "$extra" ]; then
	mkdir -p "$root/lib/extra"
	cp "$extra"/*.ko "$extra/order" "$root/lib/extra/"
fi
if [ -n "$dmsetup" ]; then
	for f in "$dmsetup" $(ldd "$dmsetup" | grep -oE '/[^ ]+'); do
		cp --parents -L --no-preserve=mode "$f" "$root/"
		chmod +x "$root/$f"
	done
	ln -s "$dmsetup" "$root/sbin/dmsetup"
fi
(cd "$root" && find . | cpio -o -H newc --quiet | gzip -1) > "$out"
echo "wrote $out"
