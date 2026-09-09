#!/usr/bin/env python3
"""Install ROM hex into the r7/r8 CPU without reformatting the user's schematic.

Program images are offsets from F000 (up to 4096 bytes, including reset vector).
Control images: r7 uses 2048 x 42 bits; r8 uses 4096 x 45 bits.
The destination ROM determines the required format; its boot bank is rebuilt.
"""
import argparse
import json
from pathlib import Path
import re
import tomllib

BOOT_IDLE = 0x600009F7F1
BOOT_IDLE_R8 = BOOT_IDLE | (1 << 44)  # Release active-low PCH_OE_N during boot.
STRING = r'"(?:[^"\\]|\\.)*"'
MEMORY = re.compile(r'\bm\s*=\s*' + STRING)


def hex_words(text):
    text = re.sub(r'(?m)(#|;|//).*$', '', text)
    return [int(v, 16) for v in text.split()]


def update(text, program=None, control=None):
    document = tomllib.loads(text)
    if document.get('format_version') != 2:
        raise ValueError('expected TOML format_version = 2')
    replacements = {}
    if program is not None:
        if not 4094 <= len(program) <= 4096 or any(not 0 <= b <= 255 for b in program):
            raise ValueError('program must be 4094..4096 bytes, based at F000 and including FFFC/FFFD')
        replacements['program'] = list(program) + [0] * (4096 - len(program))
    if control is not None:
        replacements['control'] = list(control)
    start = text.index('[workspace]')
    end_match = re.search(r'(?m)^\[', text[start + len('[workspace]'):])
    end = start + len('[workspace]') + end_match.start() if end_match else len(text)
    section = text[start:end]
    lines = section.splitlines(keepends=True)
    kind = 'NODE'
    found = set()
    for i, line in enumerate(lines):
        if not line.lstrip().startswith('{'):
            continue
        row = tomllib.loads('row = ' + line.strip().removesuffix(','))['row']
        kind = row.get('t', kind)
        if kind != 'ROM':
            continue
        label = 'program' if row.get('dw', 8) == 8 else 'control' if row.get('dw') in (42, 45) else ''
        if label not in replacements:
            continue
        width = row.get('dw', 8)
        expected_aw = 13 if width == 45 else 12
        if row.get('aw') != expected_aw or 'mf' in row:
            raise ValueError(f'expected inline {width}-bit ROM with aw={expected_aw}')
        if label in found:
            raise ValueError('ambiguous ROM: ' + label)
        values = replacements[label]
        if label == 'control':
            count = 4096 if width == 45 else 2048
            if len(values) != count or any(not 0 <= w < (1 << width) for w in values):
                raise ValueError(f'control image must be {count} words of {width} bits')
            idle = BOOT_IDLE_R8 if width == 45 else BOOT_IDLE
            values = values + [idle] * count
        if hex_words(row.get('m', '')) == values:
            found.add(label)
            continue
        memory = ' '.join(f'{w:0{(width + 3) // 4}X}' for w in values)
        lines[i], count = MEMORY.subn('m = ' + json.dumps(memory), line)
        if count != 1:
            raise ValueError('expected exactly one inline m string in ROM')
        found.add(label)
    if found != set(replacements):
        raise ValueError('missing CPU ROM: ' + ', '.join(set(replacements) - found))
    result = text[:start] + ''.join(lines) + text[end:]
    tomllib.loads(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('toml', type=Path)
    parser.add_argument('--program', type=Path, help='hex bytes, offsets from F000')
    parser.add_argument('--control', type=Path, help='r7: 2048x42 or r8: 4096x45 lcct control hex')
    parser.add_argument('-o', '--output', type=Path, help='default: update TOML in place')
    args = parser.parse_args()
    if not args.program and not args.control:
        parser.error('provide --program and/or --control')
    try:
        result = update(args.toml.read_text(),
                        hex_words(args.program.read_text()) if args.program else None,
                        hex_words(args.control.read_text()) if args.control else None)
        destination = args.output or args.toml
        destination.write_text(result)
        print(destination)
    except (ValueError, OSError) as exc:
        parser.exit(1, f'cpu65c02_image: {exc}\n')


if __name__ == '__main__':
    main()
