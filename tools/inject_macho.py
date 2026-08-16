#!/usr/bin/env python3
"""向 Mach-O（含通用二进制）注入 LC_LOAD_DYLIB，让应用启动时加载翻译动态库。"""
import struct, sys

LC_REQ_DYLD = 0x80000000
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0xc
MH_MAGIC_64 = 0xfeedfacf
FAT_MAGIC = 0xcafebabe
FAT_MAGIC_64 = 0xcafebabf

def inject_thin(buf, dylib_path, is_le=True):
    """对一个 thin Mach-O 64 注入 LC_LOAD_DYLIB，返回新 bytes。"""
    endian = '<' if is_le else '>'
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, res = struct.unpack_from(endian + '8I', buf, 0)
    assert magic == MH_MAGIC_64, f'not MH_MAGIC_64: {magic:#x}'
    # 遍历 load commands，确定插入点与最小节数据偏移
    off = 32
    min_data = len(buf)
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from(endian + '2I', buf, off)
        if cmd == LC_SEGMENT_64:
            segname = buf[off+8:off+24].rstrip(b'\0').decode()
            fileoff, filesize = struct.unpack_from(endian + '2Q', buf, off + 40)
            nsects = struct.unpack_from(endian + 'I', buf, off + 64)[0]
            soff = off + 72
            for _ in range(nsects):
                # section_64: sectname(16) segname(16) addr(8) size(8) offset(4)@48
                sectoff = struct.unpack_from(endian + 'I', buf, soff + 48)[0]
                if sectoff > 0:
                    min_data = min(min_data, sectoff)
                soff += 80
            if segname == '__LINKEDIT':
                min_data = min(min_data, fileoff)
        off += cmdsize
    insert_at = off
    # 构造新命令
    pathb = dylib_path.encode()
    cmdsize = (24 + len(pathb) + 7) & ~7
    cmd = struct.pack(endian + '4I', LC_LOAD_DYLIB, cmdsize, 24, 0)
    cmd += struct.pack(endian + '2I', 0, 0x10000)
    cmd += pathb + b'\0' * (cmdsize - 24 - len(pathb))
    assert len(cmd) == cmdsize
    if insert_at + cmdsize > min_data:
        raise RuntimeError(f'no room: insert {insert_at:#x}+{cmdsize} > data {min_data:#x}')
    out = bytearray(buf)
    out[insert_at:insert_at] = cmd
    struct.pack_into(endian + '2I', out, 16, ncmds + 1, sizeofcmds + cmdsize)
    return bytes(out)

def build_dylib_cmd(dylib_path, is_le=True):
    endian = '<' if is_le else '>'
    pathb = dylib_path.encode()
    cmdsize = (24 + len(pathb) + 7) & ~7
    cmd = struct.pack(endian + '4I', LC_LOAD_DYLIB, cmdsize, 24, 0)
    cmd += struct.pack(endian + '2I', 0, 0x10000)
    cmd += pathb + b'\0' * (cmdsize - 24 - len(pathb))
    assert len(cmd) == cmdsize
    return cmd

def find_insert_point(buf, is_le=True):
    """返回 (insert_at, min_data)：load commands 结束位置与第一节数据偏移。"""
    endian = '<' if is_le else '>'
    ncmds, sizeofcmds = struct.unpack_from(endian + '2I', buf, 16)
    off = 32
    min_data = len(buf)
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from(endian + '2I', buf, off)
        if cmd == LC_SEGMENT_64:
            segname = buf[off+8:off+24].rstrip(b'\0').decode()
            fileoff, filesize = struct.unpack_from(endian + '2Q', buf, off + 40)
            nsects = struct.unpack_from(endian + 'I', buf, off + 64)[0]
            soff = off + 72
            for _ in range(nsects):
                sectoff = struct.unpack_from(endian + 'I', buf, soff + 48)[0]
                if sectoff > 0:
                    min_data = min(min_data, sectoff)
                soff += 80
            if segname == '__LINKEDIT':
                min_data = min(min_data, fileoff)
        off += cmdsize
    return off, min_data

def main(path, dylib_path):
    data = open(path, 'rb').read()
    magic_be = struct.unpack_from('>I', data, 0)[0]
    out = bytearray(data)
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        is64 = magic_be == FAT_MAGIC_64
        nfat = struct.unpack_from('>I', data, 4)[0]
        pos = 8
        archs = []
        for _ in range(nfat):
            if is64:
                cputype, cpusub, offset, size, align, resv = struct.unpack_from('>6I', data, pos)
                pos += 32
            else:
                cputype, cpusub, offset, size, align = struct.unpack_from('>5I', data, pos)
                pos += 20
            archs.append((offset, size))
        for offset, size in archs:
            thin = bytes(out[offset:offset+size])
            insert_at, min_data = find_insert_point(thin)
            cmd = build_dylib_cmd(dylib_path)
            assert insert_at + len(cmd) <= min_data, \
                f'no room in slice@{offset:#x}: {insert_at:#x}+{len(cmd)} > {min_data:#x}'
            # 覆盖 load commands 之后的填充空白（不移动任何数据）
            gap = bytes(out[offset+insert_at:offset+insert_at+len(cmd)])
            assert set(gap) <= {0}, f'gap not empty at {offset+insert_at:#x}'
            out[offset+insert_at:offset+insert_at+len(cmd)] = cmd
            ncmds, sizeofcmds = struct.unpack_from('<2I', out, offset+16)
            struct.pack_into('<2I', out, offset+16, ncmds+1, sizeofcmds+len(cmd))
        open(path, 'wb').write(bytes(out))
        print(f'injected into {nfat} slices (in-place, no resize): {path}')
    else:
        insert_at, min_data = find_insert_point(data)
        cmd = build_dylib_cmd(dylib_path)
        assert insert_at + len(cmd) <= min_data, 'no room'
        o = bytearray(data)
        o[insert_at:insert_at] = cmd
        struct.pack_into('<2I', o, 16, struct.unpack_from('<2I', o, 16)[0]+1,
                         struct.unpack_from('<2I', o, 16)[1]+len(cmd))
        open(path, 'wb').write(bytes(o))
        print(f'injected thin: {path}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
