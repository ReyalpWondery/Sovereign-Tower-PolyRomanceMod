#!/usr/bin/env python3
"""Sovereign Tower PCK 补丁工具
解析 Godot 4.x PCK (format v3, PACK_REL_FILEBASE)，支持追加/替换文件。
补丁方式：新数据追加到文件末尾，重写目录，原数据不动（安全、可校验）。
"""
import struct
import sys
import hashlib
import os

MAGIC = b"GDPC"


class PckEntry:
    __slots__ = ("path", "offset", "size", "md5", "flags")

    def __init__(self, path, offset, size, md5, flags):
        self.path = path
        self.offset = offset      # 存储值（相对 file_base）
        self.size = size
        self.md5 = md5
        self.flags = flags


class Pck:
    def __init__(self, path):
        self.path = path
        self.entries = []
        with open(path, "rb") as f:
            header = f.read(112)
            pack_ver, vmaj, vmin, vpatch, flags = struct.unpack("<5I", header[4:24])
            if header[:4] != MAGIC:
                raise ValueError("不是有效的 PCK 文件")
            self.pack_version = pack_ver
            self.engine_version = (vmaj, vmin, vpatch)
            self.flags = flags
            self.file_base = struct.unpack("<Q", header[0x18:0x20])[0]
            self.dir_offset = struct.unpack("<Q", header[0x20:0x28])[0]
            f.seek(self.dir_offset)
            count = struct.unpack("<I", f.read(4))[0]
            if count <= 0 or count > 1000000:
                raise ValueError("目录文件数异常: %d" % count)
            for _ in range(count):
                (plen,) = struct.unpack("<I", f.read(4))
                path = f.read(plen).rstrip(b"\x00").decode("utf-8")
                off, size = struct.unpack("<QQ", f.read(16))
                md5 = f.read(16)
                (eflags,) = struct.unpack("<I", f.read(4))
                self.entries.append(PckEntry(path, off, size, md5, eflags))
        self.by_path = {e.path: e for e in self.entries}

    def _lookup(self, res_path):
        if res_path in self.by_path:
            return self.by_path[res_path]
        stripped = res_path.replace("res://", "", 1)
        if stripped in self.by_path:
            return self.by_path[stripped]
        raise KeyError(res_path)

    def has_file(self, res_path):
        try:
            self._lookup(res_path)
            return True
        except KeyError:
            return False

    def read_file(self, res_path):
        e = self._lookup(res_path)
        with open(self.path, "rb") as f:
            f.seek(e.offset + self.file_base)
            return f.read(e.size)

    def verify_file(self, res_path):
        e = self._lookup(res_path)
        return hashlib.md5(self.read_file(res_path)).digest() == e.md5


def patch_pck(pck_path, replacements):
    """replacements: dict { 'res://path/in/pck': '/local/file/path' }
    追加数据并重写目录（原地修改，调用前请先备份）。"""
    pck = Pck(pck_path)

    # 读取所有补丁数据（键统一为 pck 内部使用的无前缀路径）
    patches = {}
    for res_path, local in replacements.items():
        with open(local, "rb") as f:
            data = f.read()
        patches[res_path.replace("res://", "", 1)] = data

    with open(pck_path, "r+b") as f:
        f.seek(0, os.SEEK_END)
        write_pos = f.tell()

        # 追加新数据（4 字节对齐）
        new_locations = {}  # res_path -> (stored_offset, size, md5)
        for res_path, data in patches.items():
            pad = (4 - write_pos % 4) % 4
            if pad:
                f.write(b"\x00" * pad)
                write_pos += pad
            f.write(data)
            new_locations[res_path] = (write_pos - pck.file_base, len(data), hashlib.md5(data).digest())
            write_pos += len(data)

        # 构造新目录
        out_entries = []
        patched_paths = set()
        for e in pck.entries:
            if e.path in patches:
                off, size, md5 = new_locations[e.path]
                out_entries.append((e.path, off, size, md5, e.flags))
                patched_paths.add(e.path)
            else:
                out_entries.append((e.path, e.offset, e.size, e.md5, e.flags))
        for res_path in patches:
            if res_path not in patched_paths:
                off, size, md5 = new_locations[res_path]
                out_entries.append((res_path, off, size, md5, 0))

        # 写目录（对齐 4）
        pad = (4 - write_pos % 4) % 4
        if pad:
            f.write(b"\x00" * pad)
            write_pos += pad
        new_dir_offset = write_pos
        f.write(struct.pack("<I", len(out_entries)))
        for path, off, size, md5, eflags in out_entries:
            pb = path.encode("utf-8")
            plen = len(pb)
            padded = plen + ((4 - plen % 4) % 4)
            f.write(struct.pack("<I", padded))
            f.write(pb + b"\x00" * (padded - plen))
            f.write(struct.pack("<QQ", off, size))
            f.write(md5)
            f.write(struct.pack("<I", eflags))

        # 更新头部目录偏移
        f.seek(0x20)
        f.write(struct.pack("<Q", new_dir_offset))

    # 校验：重新解析并抽查
    pck2 = Pck(pck_path)
    for res_path in patches:
        if res_path not in pck2.by_path:
            raise RuntimeError("补丁后目录缺少: " + res_path)
        if not pck2.verify_file(res_path):
            raise RuntimeError("补丁后文件校验失败: " + res_path)
    print("补丁完成，共写入 %d 个文件，已校验。" % len(patches))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "list":
        pck = Pck(sys.argv[2])
        print("pack_version=%d engine=%s flags=0x%x file_base=%d dir_offset=0x%x entries=%d" % (
            pck.pack_version, pck.engine_version, pck.flags, pck.file_base, pck.dir_offset, len(pck.entries)))
        for e in pck.entries[:int(sys.argv[3]) if len(sys.argv) > 3 else 10]:
            print(e.path, e.offset, e.size)
    elif len(sys.argv) >= 4 and sys.argv[1] == "extract":
        pck = Pck(sys.argv[2])
        data = pck.read_file(sys.argv[3])
        out = sys.argv[4] if len(sys.argv) > 4 else os.path.basename(sys.argv[3])
        with open(out, "wb") as f:
            f.write(data)
        print("extracted %s (%d bytes), md5 ok: %s" % (sys.argv[3], len(data), pck.verify_file(sys.argv[3])))
    else:
        print("usage: pck_tool.py list <pck> [n] | extract <pck> <res://path> [out]")
