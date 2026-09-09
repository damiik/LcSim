import importlib.util
from pathlib import Path
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cpu_image', ROOT / 'tools/cpu65c02_image.py')
image = importlib.util.module_from_spec(spec)
spec.loader.exec_module(image)


class CpuImage(unittest.TestCase):
    def test_current_image_and_boot_bank(self):
        source = (ROOT / 'examples/cpu65c02.toml').read_text()
        program = image.hex_words((ROOT / 'examples/cpu65c02-absolute-call.hex').read_text())
        gates = tomllib.loads(source)['workspace']['gates']
        control = next(g for g in gates if g.get('dw') == 45)
        control_words = image.hex_words(control['m'])
        self.assertEqual(control_words[4096:], [image.BOOT_IDLE_R8] * 4096)
        # Installing the checked-in image and r8 bank is a byte-for-byte no-op.
        self.assertEqual(image.update(source, program, control_words[:4096]), source)
        self.assertEqual(program[0xffc:0xffe], [0x00, 0xf0])

    def test_invalid_size_and_overflow(self):
        source = (ROOT / 'examples/cpu65c02.toml').read_text()
        for program in ([0] * 44, [0] * 4097, [256] * 4096):
            with self.assertRaises(ValueError):
                image.update(source, program=program)
        for control in ([0] * 2048, [1 << 45] * 4096):
            with self.assertRaises(ValueError):
                image.update(source, control=control)

    def test_program_update_keeps_layout_and_control(self):
        source = (ROOT / 'examples/cpu65c02.toml').read_text()
        program = [0] * 4094
        program[0xffc:0xffe] = [0x20, 0xf3]
        updated = image.update(source, program=program)
        before, after = tomllib.loads(source), tomllib.loads(updated)
        changed = []
        for index, (a, b) in enumerate(zip(before['workspace']['gates'], after['workspace']['gates'])):
            if a != b:
                changed.append(index)
                self.assertEqual({k: v for k, v in a.items() if k != 'm'},
                                 {k: v for k, v in b.items() if k != 'm'})
        self.assertEqual(changed, [15])

    def test_r7_rom_still_supported_and_r8_image_rejected(self):
        source = 'format_version = 2\n[workspace]\ngates = [\n{t="ROM", aw=12, dw=42, m=""},\n]\n'
        updated = image.update(source, control=[0]*2048)
        words = image.hex_words(tomllib.loads(updated)['workspace']['gates'][0]['m'])
        self.assertEqual(words[2048:], [image.BOOT_IDLE]*2048)
        with self.assertRaises(ValueError):
            image.update(source, control=[0]*4096)

    def test_ambiguous_equal_image_is_rewritten(self):
        source = (ROOT / 'examples/cpu65c02.toml').read_text()
        gates = tomllib.loads(source)['workspace']['gates']
        control = next(g for g in gates if g.get('dw') == 45)
        words = image.hex_words(control['m'])[:4096]
        old = source.replace('0x', '')
        fixed = image.update(old, control=words)
        self.assertIn('0x106180099773', fixed)
        self.assertNotEqual(old, fixed)
        self.assertEqual(image.update(fixed, control=words), fixed)
        for row in tomllib.loads(source)['workspace']['gates']:
            if row.get('m'):
                self.assertTrue(all(w.startswith('0x') for w in row['m'].split()))

    def test_canonical_hex_preserves_words_and_other_properties(self):
        source = 'format_version=2\n[workspace]\ngates=[\n{t="ROM", m="20 55 106180099773 0b10", n="USER", x=42},\n]\n'
        fixed = image.canonicalize_hex_memories(source)
        row = tomllib.loads(fixed)['workspace']['gates'][0]
        self.assertEqual(row['m'], '0x20 0x55 0x106180099773 0x2')
        self.assertEqual(row['x'], 42)
        self.assertEqual(row['n'], 'USER')
        self.assertEqual(image.canonicalize_hex_memories(fixed), fixed)
