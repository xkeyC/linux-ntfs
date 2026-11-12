# ntfs: fatal signal during a metadata read — reproducers and logs

Test material for the patch "ntfs: don't let a fatal signal interrupt
metadata reads" (branch `fix-eintr-metadata-update` of this repository, and
the same change against linkinjeon/ntfs.git `ntfs-next`).

`read_mapping_folio()` returns -EINTR when the caller has a fatal signal
pending while it waits for its read. ntfs treats that as a volume error, so
with `errors=remount-ro` killing a task that waits on a metadata read turns
the volume read-only, and if the read was part of an update (unlink, a
directory index update, an allocation) the update stops half way.

These scripts boot a small QEMU guest, run one operation on an NTFS image
with reads throttled to 40 IOPS, kill it partway through after
`drop_caches`, and check whether the volume went read-only. After the run,
the host checks the image with `ntfsck -n`. **Only use them on scratch
images**: the unpatched driver damages the volume.

## Requirements

- QEMU with KVM.
- A kernel `bzImage` with the ntfs driver as a module. `kernel/vm.config`
  is the fragment used for the logs below (KASAN, lockdep, hung task
  detection, fault injection, dm-delay, virtio built in). For example, in an
  ntfs-next tree:

      make O=build defconfig kvm_guest.config
      scripts/kconfig/merge_config.sh -m -O build build/.config vm.config
      scripts/config --file build/.config -d LOCALVERSION_AUTO
      make O=build olddefconfig && make O=build -j$(nproc) bzImage modules

  Disabling `LOCALVERSION_AUTO` keeps the vermagic stable, so modules built
  from other trees later still load.
- Two `ntfs.ko` built against that kernel: one without and one with the
  patch, e.g. `make -C <tree> O=build M=<copy of fs/ntfs> modules`.
- A static busybox, `mkntfs` and `ntfsck` (ntfsprogs-plus).
- `dmsetup`, only for the `eio` scenario.
- `tools/ntfs-stream`, only for the `stream` scenario: a static build of
  `tools/ntfs-stream.c`, e.g. `gcc -static -O2 -o ntfs-stream tools/ntfs-stream.c`.

## Usage

    scripts/mkinitramfs.sh -o initrd.gz -b /path/to/busybox \
        -m base=/path/to/unpatched/ntfs.ko -m fix=/path/to/patched/ntfs.ko \
        [-d /path/to/dmsetup] [-e dir-with-virtio-modules] [-x ntfs-stream]
    scripts/mkimages.sh bzImage initrd.gz fix img/
    scripts/matrix.sh bzImage initrd.gz img/ out/ scripts/matrix-example.txt 4

`mkimages.sh` creates sparse 40 GiB templates (a few tens of MiB on disk).
Every run works on a fresh copy of one of them, made with
`cp --reflink=auto`. `scripts/run.sh` runs a single scenario. With a
distro kernel that has virtio as modules, pass them with `-e` (see
`mkinitramfs.sh`).

Each run prints one line:

    spread-base-KILL: ro_after_trial=2 | ntfsck: 5 errors left (errors:5, fixed:0)

`ro_after_trial=N` means the volume went read-only in run N; `none` means
it stayed read-write for all runs. For `mount`, the `=== trial` lines in the
log say whether each killed mount failed or mounted read-write or read-only.
The `.log` file has the kernel messages, and the `.fsck` file has the
ntfsck output.

## Scenarios (scripts/guest-init)

| scenario | operation that is killed | path it exercises |
|---|---|---|
| `spread` | `rm` of 12 files, each in a different 128 MiB `$Bitmap` page | cluster freeing at eviction, MFT record freeing |
| `bigfile` | `rm` of a 512 MiB file whose run spans 4 `$Bitmap` pages | the same, across `$Bitmap` pages |
| `dir-rm` | `rm` of 40 files in a directory with 4000 long names | directory lookup and index entry removal |
| `lookup` | `ls -l` of that directory | readdir and lookup (issue #98) |
| `dir-create` | creating files between the existing names | index insert (not reached, see below) |
| `falloc` | `fallocate -l 6G` | cluster and MFT record allocation |
| `write` | `dd bs=1M count=400 conv=fsync` | cluster allocation during writeback |
| `stream` | rewriting 100 bytes in each page of an 8 MiB named stream through `NTFS_IOC_STREAM_WRITE` | read-modify-write of a non-resident named stream |
| `mount` | `mount` | the mount-time reads of `$MFT`, `$MFTMirr`, `$LogFile`, `$AttrDef`, `$UpCase`, `$BadClus` |
| `eio` | `rm` as in `spread`, while reads are delayed by dm-delay and then failed with `fail_make_request` | a read that is interrupted and then fails |

## Results in logs/

Twenty runs per scenario, SIGKILL unless the name says TERM.

`logs/ntfs-next/` (patch v1): the kernel is linkinjeon/ntfs.git `ntfs-next`
at 2b4bb6d6d with `kernel/vm.config`. `base` is the unpatched driver and
`v3` is the driver with patch v1.

| scenario | base | v3 |
|---|---|---|
| spread | read-only in run 2, ntfsck: 5 errors | clean (KILL and TERM) |
| bigfile | read-only in run 2, ntfsck: 60 errors | clean |
| dir-rm | read-only in run 1 (lookup) | clean (KILL and TERM) |
| lookup | read-only in run 1 | clean (KILL and TERM) |
| falloc | read-only in run 1 | clean |
| write | read-only in run 8 | clean |
| dir-create | — | clean, but the kills land in the lookup |
| eio | — | read-only from the real I/O error, `error -5` instead of -4, task exits |

There were no KASAN, lockdep or hung task reports in any run.

`logs/ntfs-next-v2/` (patch v2): the same kernel. `base` is the unpatched
driver, `v1` and `v2` are the driver with patch v1 and v2.

| scenario | base | v1 | v2 |
|---|---|---|---|
| stream | read-only in run 1 (`__ntfs_inode_non_resident_attr_pwrite(): Failed to read a page 6 for attr 0x80: -4`) | clean | clean (KILL and TERM) |
| mount | the killed mount failed in all 20 runs, with bogus `$UpCase` and `$AttrDef` errors | — | mounted read-write in all 20 runs (KILL and TERM) |
| spread, bigfile, dir-rm, lookup, falloc, write | see above | see above | clean |
| eio | — | — | read-only from the real I/O error, `error -5`, task exits |

Again no KASAN, lockdep or hung task reports.

`logs/v7.3.1/`: the NixOS v7.3.1 kernel. `n731base` is v7.3.1 plus the
ntfs fixes queued for 7.3.y and a local workaround for the lookup case.
`n731v3` adds the patch, and `ghv3` is the out-of-tree port from this
repository. In `dir-rm`, the base driver went read-only in run 2 and
ntfsck reported 4001 errors: the whole directory index was damaged.

Earlier runs, in which only the lookups were kept from failing, also showed
index damage after `dir-rm`: ntfsck reported "Subnode ... is not set on
$BITMAP" and entries pointing to freed records.

## Limits

- The runs depend on timing. The kill delays vary per run, but whether a
  given run hits a read in flight depends on the host.
- `dir-create` never reached an index insert or split, because the kill
  always landed in the lookup that precedes it.
- Only QEMU virtio disks were tested.
