#!/usr/bin/env python3
"""Repair broken library symlinks in the userland sysroot.

`cpio -idm` extracts the versioned real file and the `.so` convenience
symlink, but the intermediate `.so.N` link is sometimes missing, which breaks
`-lfoo` at link time. This recreates any missing intermediate link by
resolving the SONAME pattern locally.

Run:  python3 tool/repair_sysroot_links.py /data/toolchain/sysroot
"""
import os
import re
import sys

VERSIONED = re.compile(r"^(?P<stem>.+)\.so\.(?P<major>\d+)\.(?P<rest>.+)$")
SONAME = re.compile(r"^(?P<stem>.+)\.so\.(?P<major>\d+)$")


def main(root: str) -> int:
    libdirs = []
    for base, dirs, _files in os.walk(root):
        if os.path.basename(base) == "lib64" or base.endswith("/lib"):
            libdirs.append(base)

    # Index every real file by its basename.
    real = {}
    for libdir in libdirs:
        for entry in os.listdir(libdir):
            path = os.path.join(libdir, entry)
            if os.path.isfile(path) and not os.path.islink(path):
                real.setdefault(entry, path)

    fixed = []
    for libdir in libdirs:
        for entry in os.listdir(libdir):
            path = os.path.join(libdir, entry)
            if not os.path.islink(path):
                continue
            target = os.readlink(path)
            if os.path.exists(os.path.join(libdir, target)):
                continue
            # `libfoo.so -> libfoo.so.2` and `libfoo.so.2` is missing but
            # `libfoo.so.2.1.0` exists.
            if not SONAME.match(target):
                continue
            candidates = [
                name
                for name in real
                if name.startswith(target + ".")
            ]
            if not candidates:
                continue
            candidates.sort()
            link = os.path.join(libdir, target)
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(candidates[0], link)
            fixed.append(f"{libdir}/{target} -> {candidates[0]}")

    for line in fixed:
        print("fixed", line)
    print(f"{len(fixed)} links repaired")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/data/toolchain/sysroot"))
