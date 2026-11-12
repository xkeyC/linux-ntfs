// SPDX-License-Identifier: GPL-2.0
/*
 * Write to a named stream through NTFS_IOC_STREAM_WRITE.
 *
 *   ntfs-stream fill FILE NAME PAGES   write PAGES full, page-aligned pages
 *   ntfs-stream poke FILE NAME PAGES   write 100 bytes at offset 8 of each
 *                                      page, one ioctl per page, so every
 *                                      write reads its page first
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

/* From include/uapi/linux/ntfs.h */
struct ntfs_stream {
	uint64_t stream_offset;
	uint64_t io_len;
	uint64_t bytes_returned;
	uint32_t name_len;
	uint32_t flags;
	uint64_t reserved;
	uint8_t buffer[];
};
#define NTFS_IOC_MAGIC		0xEF
#define NTFS_IOC_STREAM_WRITE	_IOWR(NTFS_IOC_MAGIC, 2, struct ntfs_stream)

#define PAGE	4096

static int stream_write(int fd, const char *name, uint64_t off,
			const void *data, size_t len)
{
	size_t nlen = strlen(name);
	struct ntfs_stream *req = calloc(1, sizeof(*req) + nlen + len);

	if (!req)
		return -1;
	req->stream_offset = off;
	req->io_len = len;
	req->name_len = nlen;
	memcpy(req->buffer, name, nlen);
	memcpy(req->buffer + nlen, data, len);
	if (ioctl(fd, NTFS_IOC_STREAM_WRITE, req) < 0) {
		free(req);
		return -1;
	}
	free(req);
	return 0;
}

int main(int argc, char **argv)
{
	static char page[PAGE];
	long pages, i;
	int fd;

	if (argc != 5) {
		fprintf(stderr, "usage: %s fill|poke FILE NAME PAGES\n", argv[0]);
		return 2;
	}
	pages = atol(argv[4]);
	fd = open(argv[2], O_RDWR | O_CREAT, 0644);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	memset(page, 0x5a, sizeof(page));
	for (i = 0; i < pages; i++) {
		int full = !strcmp(argv[1], "fill");
		uint64_t off = (uint64_t)i * PAGE + (full ? 0 : 8);

		if (stream_write(fd, argv[3], off, page, full ? PAGE : 100)) {
			perror("NTFS_IOC_STREAM_WRITE");
			return 1;
		}
	}
	close(fd);
	return 0;
}
