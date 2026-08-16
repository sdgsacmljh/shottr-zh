#!/usr/bin/env python3
"""Safely add LC_LOAD_DYLIB to 64-bit thin or universal Mach-O files."""

from __future__ import annotations

import os
import struct
import sys

LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0xC
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF


class MachOError(RuntimeError):
    pass


def dylib_command(dylib_path: str) -> bytes:
    path = dylib_path.encode("utf-8") + b"\0"
    cmdsize = (24 + len(path) + 7) & ~7
    command = struct.pack("<6I", LC_LOAD_DYLIB, cmdsize, 24, 0, 0, 0x10000)
    return command + path + bytes(cmdsize - 24 - len(path))


def load_command_layout(buf: bytes, base: int, size: int) -> tuple[int, int, int, int]:
    if size < 32 or base < 0 or base + size > len(buf):
        raise MachOError("invalid Mach-O slice bounds")
    magic = struct.unpack_from("<I", buf, base)[0]
    if magic != MH_MAGIC_64:
        raise MachOError(f"unsupported Mach-O magic at {base:#x}: {magic:#x}")
    ncmds, sizeofcmds = struct.unpack_from("<2I", buf, base + 16)
    commands_start = base + 32
    commands_end = commands_start + sizeofcmds
    if commands_end > base + size:
        raise MachOError("load commands exceed slice bounds")
    return ncmds, sizeofcmds, commands_start, commands_end


def inspect_slice(buf: bytes, base: int, size: int, dylib_path: str) -> tuple[int, int, int, int]:
    ncmds, sizeofcmds, commands_start, _ = load_command_layout(buf, base, size)
    offset = commands_start
    min_data = base + size
    found = False

    for _ in range(ncmds):
        if offset + 8 > base + size:
            raise MachOError("truncated load command")
        cmd, cmdsize = struct.unpack_from("<2I", buf, offset)
        if cmdsize < 8 or offset + cmdsize > base + size:
            raise MachOError("invalid load command size")
        if cmd == LC_LOAD_DYLIB and cmdsize >= 24:
            name_offset = struct.unpack_from("<I", buf, offset + 8)[0]
            if 0 < name_offset < cmdsize:
                raw = buf[offset + name_offset : offset + cmdsize].split(b"\0", 1)[0]
                found = raw.decode("utf-8", "replace") == dylib_path
        if cmd == LC_SEGMENT_64:
            if cmdsize < 72:
                raise MachOError("invalid LC_SEGMENT_64 command")
            fileoff = struct.unpack_from("<Q", buf, offset + 40)[0]
            nsects = struct.unpack_from("<I", buf, offset + 64)[0]
            sections_end = offset + 72 + nsects * 80
            if sections_end > offset + cmdsize:
                raise MachOError("section table exceeds segment command")
            section = offset + 72
            for _ in range(nsects):
                section_offset = struct.unpack_from("<I", buf, section + 48)[0]
                if section_offset:
                    min_data = min(min_data, base + section_offset)
                section += 80
            segname = buf[offset + 8 : offset + 24].rstrip(b"\0")
            if segname == b"__LINKEDIT" and fileoff:
                min_data = min(min_data, base + fileoff)
        offset += cmdsize

    if offset != base + 32 + sizeofcmds:
        raise MachOError("load command sizes do not match sizeofcmds")
    if found:
        raise MachOError(f"dylib is already injected in slice at {base:#x}")
    return ncmds, sizeofcmds, offset, min_data


def inject_slice(out: bytearray, base: int, size: int, dylib_path: str) -> None:
    ncmds, sizeofcmds, insert_at, min_data = inspect_slice(bytes(out), base, size, dylib_path)
    command = dylib_command(dylib_path)
    if insert_at + len(command) > min_data:
        raise MachOError(
            f"no load-command padding in slice at {base:#x}: "
            f"{insert_at:#x}+{len(command)} > {min_data:#x}"
        )
    gap = out[insert_at : insert_at + len(command)]
    if any(gap):
        raise MachOError(f"load-command padding is not empty in slice at {base:#x}")
    out[insert_at : insert_at + len(command)] = command
    struct.pack_into("<2I", out, base + 16, ncmds + 1, sizeofcmds + len(command))


def slices(data: bytes) -> list[tuple[int, int]]:
    if len(data) < 4:
        raise MachOError("file is too small")
    magic_be = struct.unpack_from(">I", data, 0)[0]
    if magic_be not in (FAT_MAGIC, FAT_MAGIC_64):
        load_command_layout(data, 0, len(data))
        return [(0, len(data))]

    if len(data) < 8:
        raise MachOError("truncated universal header")
    count = struct.unpack_from(">I", data, 4)[0]
    if count < 1 or count > 32:
        raise MachOError(f"invalid architecture count: {count}")
    result: list[tuple[int, int]] = []
    pos = 8
    for _ in range(count):
        if magic_be == FAT_MAGIC_64:
            if pos + 32 > len(data):
                raise MachOError("truncated fat_arch_64")
            _, _, offset, size, _, _ = struct.unpack_from(">IIQQII", data, pos)
            pos += 32
        else:
            if pos + 20 > len(data):
                raise MachOError("truncated fat_arch")
            _, _, offset, size, _ = struct.unpack_from(">5I", data, pos)
            pos += 20
        load_command_layout(data, offset, size)
        result.append((offset, size))
    return result


def inject(path: str, dylib_path: str) -> int:
    with open(path, "rb") as handle:
        original = handle.read()
    targets = slices(original)
    output = bytearray(original)
    for offset, size in targets:
        inject_slice(output, offset, size, dylib_path)
    if len(output) != len(original):
        raise MachOError("internal error: file size changed")
    mode = os.stat(path).st_mode
    with open(path, "r+b") as handle:
        handle.write(output)
        handle.truncate(len(output))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(path, mode)
    return len(targets)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} MACH_O DYLIB_PATH", file=sys.stderr)
        return 2
    try:
        count = inject(sys.argv[1], sys.argv[2])
    except (OSError, MachOError, struct.error) as exc:
        print(f"inject_macho: {exc}", file=sys.stderr)
        return 1
    print(f"injected into {count} slice(s), file size unchanged: {sys.argv[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
