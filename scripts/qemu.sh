#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Boot the test initramfs once on one image and print the guest's report.
#
# usage: qemu.sh KERNEL INITRD IMAGE NTFSMOD SCENARIO SIGNAL RUNS
# THROTTLE=0 turns off the 40 IOPS read limit (used for the prep and eio runs).
set -eu
[ $# -eq 7 ] || { sed -n '3,6p' "$0"; exit 1; }
kernel=$1 initrd=$2 image=$3
th=",throttling.iops-read=40"
[ "${THROTTLE:-1}" = 0 ] && th=
timeout "${TIMEOUT:-1800}" qemu-system-x86_64 -enable-kvm -cpu host -m 3072 -smp 4 \
	-nographic -no-reboot -kernel "$kernel" -initrd "$initrd" \
	-append "console=ttyS0 rdinit=/init panic=-1 loglevel=4 ntfsmod=$4 scen=$5 sig=$6 n=$7" \
	-drive "file=$image,format=raw,if=virtio,cache=none$th" 2>&1 |
	tr -d '\r' |
	grep -aE '^===|^ *[0-9]+ |HANG|BUG|WARNING|INFO: task|Kernel panic|cut here'
