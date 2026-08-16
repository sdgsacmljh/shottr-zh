#!/usr/bin/env python3
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
DYLIB_PATH = "@executable_path/../Frameworks/shottr_zh.dylib"
SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "inject_macho.py"


def thin_macho(size=4096, dirty_padding=False):
    header = struct.pack("<8I", MH_MAGIC_64, 0x01000007, 3, 2, 0, 0, 0, 0)
    data = bytearray(header + bytes(size - len(header)))
    if dirty_padding:
        data[32] = 1
    return bytes(data)


def fat_macho(is_64=False):
    first_offset = 4096
    second_offset = 8192
    thin = thin_macho()
    output = bytearray(12288)
    if is_64:
        struct.pack_into(">2I", output, 0, FAT_MAGIC_64, 2)
        struct.pack_into(">IIQQII", output, 8, 0x01000007, 3, first_offset, len(thin), 12, 0)
        struct.pack_into(">IIQQII", output, 40, 0x0100000C, 0, second_offset, len(thin), 12, 0)
    else:
        struct.pack_into(">2I", output, 0, FAT_MAGIC, 2)
        struct.pack_into(">5I", output, 8, 0x01000007, 3, first_offset, len(thin), 12)
        struct.pack_into(">5I", output, 28, 0x0100000C, 0, second_offset, len(thin), 12)
    output[first_offset : first_offset + len(thin)] = thin
    output[second_offset : second_offset + len(thin)] = thin
    return bytes(output), (first_offset, second_offset)


class InjectMachOTests(unittest.TestCase):
    def run_injector(self, initial):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = Path(temp.name) / "fixture"
        path.write_bytes(initial)
        result = subprocess.run(
            ["python3", str(SCRIPT), str(path), DYLIB_PATH],
            text=True,
            capture_output=True,
            check=False,
        )
        return path, result

    def test_thin_binary_is_modified_in_place(self):
        initial = thin_macho()
        path, result = self.run_injector(initial)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = path.read_bytes()
        self.assertEqual(len(output), len(initial))
        ncmds, sizeofcmds = struct.unpack_from("<2I", output, 16)
        self.assertEqual(ncmds, 1)
        self.assertGreater(sizeofcmds, 24)
        self.assertIn(DYLIB_PATH.encode(), output[:512])

    def test_fat32_binary_updates_both_slices(self):
        initial, offsets = fat_macho(False)
        path, result = self.run_injector(initial)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = path.read_bytes()
        self.assertEqual(len(output), len(initial))
        for offset in offsets:
            self.assertEqual(struct.unpack_from("<I", output, offset + 16)[0], 1)

    def test_fat64_header_uses_64_bit_offsets(self):
        initial, offsets = fat_macho(True)
        path, result = self.run_injector(initial)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = path.read_bytes()
        self.assertEqual(len(output), len(initial))
        for offset in offsets:
            self.assertEqual(struct.unpack_from("<I", output, offset + 16)[0], 1)

    def test_duplicate_injection_is_rejected_without_changes(self):
        path, first = self.run_injector(thin_macho())
        self.assertEqual(first.returncode, 0, first.stderr)
        once = path.read_bytes()
        second = subprocess.run(
            ["python3", str(SCRIPT), str(path), DYLIB_PATH],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("already injected", second.stderr)
        self.assertEqual(path.read_bytes(), once)

    def test_nonzero_padding_is_rejected_without_changes(self):
        initial = thin_macho(dirty_padding=True)
        path, result = self.run_injector(initial)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("padding is not empty", result.stderr)
        self.assertEqual(path.read_bytes(), initial)


if __name__ == "__main__":
    unittest.main()
