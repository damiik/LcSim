#!/usr/bin/env python3
"""TOML v2 -> Nim design module (proof-of-concept)."""
import argparse, pathlib, re, tomllib, sys

PRIMITIVES = {'AND','OR','NOT','BUF','XOR','NAND','NOR','DFF','D_LATCH','MUX2',
              'OC','TBUF','SW','SWITCH','H','L','PULLUP','PULLDOWN','PULL',
              'CLK','NODE','INOUT','BUS','DISPLAY','OSCILLOSCOPE','ROM','RAM','TERMINAL'}
FIXED = {'TERMINAL':(26,8),'NOT':(1,1),'BUF':(1,1),'OC':(1,1),
         'DFF':(2,2),'D_LATCH':(2,2),'MUX2':(3,1),'TBUF':(2,1),
         'MUX4':(6,1),'DMUX2':(2,2),'DMUX4':(3,4),
         'SW':(3,2),'SWITCH':(3,2),'H':(0,1),'L':(0,1),
         'PULLUP':(0,1),'PULL':(0,1),'PULLDOWN':(0,1),'CLK':(0,1),
         'NODE':(1,1),'INOUT':(1,1)}
FIELDS = set('t io_base io_mode n i o x y cd nnp nsh nsz non nof nsn nst nbo hd color pc pd tsu th p aw dw delay_ns eal m mf dm bl bm in on ix s k d'.split())

GT = {
    'AND':'gtAND','OR':'gtOR','XOR':'gtXOR','NAND':'gtNAND','NOR':'gtNOR',
    'NOT':'gtNOT','BUF':'gtBUF','TBUF':'gtTBUF','OC':'gtOC','MUX2':'gtMUX2',
    'DFF':'gtDFF','D_LATCH':'gtDLATCH','SW':'gtSWITCH','SWITCH':'gtSWITCH',
    'H':'gtH','L':'gtL','PULLUP':'gtPULLUP','PULL':'gtPULLUP','PULLDOWN':'gtPULLDOWN',
    'CLK':'gtCLK','NODE':'gtNODE','INOUT':'gtINOUT','BUS':'gtBUS',
    'DISPLAY':'gtDISPLAY','OSCILLOSCOPE':'gtOSCILLOSCOPE',
    'ROM':'gtROM','RAM':'gtRAM','TERMINAL':'gtTERMINAL',
    'INPUT':'gtINPUT','OUTPUT':'gtOUTPUT',
}

def wirelist(v):
    if v is None: return []
    if isinstance(v, int) and not isinstance(v, bool): v = [v]
    if not isinstance(v, list): raise ValueError('wire must be int or array')
    return v

def nim_seq_nets(xs):
    if not xs: return '@[]'
    return '@[' + ','.join(f'Net({x})' for x in xs) + ']'

def nim_seq_u64(xs):
    if not xs: return '@[]'
    return '@[' + ','.join(f'{x}\'u64' for x in xs) + ']'

def nimstr(s):
    """Emit a Nim string literal (double-quoted, escaped)."""
    out = ['"']
    for ch in s:
        c = ord(ch)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif c < 32:
            out.append('\\x%02X' % c)
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)

def emit_element(r, module):
    t = r['t']
    enum_name = 'gtMODULE' if module >= 0 else GT.get(t, 'gtUNKNOWN')

    cycles = float(r['pc']) if 'pc' in r else -1.0
    ns = float(r['pd']) if 'pd' in r else -1.0
    setup = float(r['tsu']) if 'tsu' in r else -1.0
    hold = float(r['th']) if 'th' in r else -1.0

    period = 10
    if t == 'CLK':
        raw = r.get('p', r.get('n', '10'))
        try: period = int(raw)
        except (TypeError, ValueError): period = 10
        if period < 1: raise ValueError('CLK period must be positive')

    aw = int(r['aw']) if 'aw' in r else 4
    dw = int(r['dw']) if 'dw' in r else 8
    io_base = int(r['io_base']) if 'io_base' in r else 0xd010
    memory_ns = float(r['delay_ns']) if 'delay_ns' in r else 0.0
    io_mode = r.get('io_mode', 'apple1')
    active_low = 'true' if r.get('eal') else 'false'

    memory_field = ''
    if t in ('ROM', 'RAM'):
        mem = r.get('m', '')
        if r.get('mf'):
            mem = (r['_path'].parent / r['mf']).read_text()
        words = []
        for tok in re.sub(r'(?m)(#|;|//).*$', '', mem).split():
            try:
                words.append(int(tok, 0) if tok.lower().startswith(('0x','0b','0o')) else int(tok, 16))
            except ValueError:
                raise ValueError(f'invalid memory word {tok}')
        memory_field = f', memory: {nim_seq_u64(words)}'

    return (
        f'Element(typ: {enum_name}, name: {nimstr(r.get("n",""))}, '
        f'ins: {nim_seq_nets(r["i"])}, outs: {nim_seq_nets(r["o"])}, '
        f'module: {module}, '
        f'cycles: {cycles}, ns: {ns}, setup: {setup}, hold: {hold}, '
        f'ioMode: {nimstr(io_mode)}, '
        f'period: {period}\'u32, '
        f'aw: {aw}\'u32, dw: {dw}\'u32, ioBase: {io_base}\'u32, '
        f'memoryNs: {memory_ns}, '
        f'activeLow: {active_low}'
        f'{memory_field})'
    )

def compile_file(path, output):
    data = tomllib.loads(path.read_text())
    if data.get('format_version') != 2:
        raise ValueError('expected format_version = 2')
    tables = {k: v for k, v in data.items() if isinstance(v, dict)}
    if 'workspace' not in tables: raise ValueError('missing [workspace]')
    names = {v.get('n', k): k for k, v in tables.items()}
    if len(names) != len(tables): raise ValueError('duplicate module names')

    normalized = {}
    for key, table in tables.items():
        inherit = table.get('inherit', [])
        if not isinstance(inherit, list) or any(f not in ['t','x','y','cd','nnp'] for f in inherit):
            raise ValueError(f'{key}: invalid inherit')
        rows = {}
        for section in ['inputs', 'gates', 'outputs']:
            prev = dict(t='NODE', x=0, y=0, cd='', nnp='CENTER'); rows[section] = []
            for idx, raw in enumerate(table.get(section, [])):
                if not isinstance(raw, dict): raise ValueError(f'{key}.{section}[{idx}]: inline table expected')
                unknown = [f for f in raw if f not in FIELDS and not f.startswith('scope_')]
                if unknown: raise ValueError(f'{key}.{section}[{idx}]: unknown fields {unknown}')
                r = {f: prev[f] for f in inherit}; r.update(raw)
                prev.update({f: r[f] for f in inherit})
                if 'n' not in r and 'k' in r: r['n'] = r['k']
                if section == 'inputs' and 'o' not in r: r['o'] = r.get('ix', 0)
                if section == 'outputs' and 'i' not in r: r['i'] = r.get('s', 0)
                r['i'] = wirelist(r.get('i')); r['o'] = wirelist(r.get('o'))
                if section != 'gates':
                    r['t'] = 'INPUT' if section == 'inputs' else 'OUTPUT'
                r['_path'] = path
                rows[section].append(r)
        normalized[key] = rows

    # Resolve multi-driver pins: a nested input array denotes multiple
    # drivers of ONE pin, not more pins. Identical to the C++ compiler.
    for key, rows in normalized.items():
        parent = {}
        def root(n):
            parent.setdefault(n, n)
            if parent[n] != n:
                parent[n] = root(parent[n])
            return parent[n]
        allrows = sum(rows.values(), [])
        for row in allrows:
            for pin in row['i']:
                if isinstance(pin, list):
                    if not pin:
                        raise ValueError(f'{key}: empty multi-driver pin')
                    for w in pin[1:]:
                        parent[root(w)] = root(pin[0])
            if any(isinstance(w, list) for w in row['o']):
                raise ValueError(f'{key}: nested output array is invalid')
        for row in allrows:
            row['i'] = [root(w[0] if isinstance(w, list) else w) for w in row['i']]
            row['o'] = [root(w) for w in row['o']]

    keys = list(tables)
    ids = {k: i for i, k in enumerate(keys)}
    # Display name ("D_FF") -> integer definition index, matching `d.root`
    # and `Element.module` conventions of the C++ compiler.
    name_to_id = {n: ids[k] for n, k in names.items()}

    # Port count validation & padding.
    for k, rows in normalized.items():
        for r in rows['gates']:
            t = r['t']
            module = name_to_id.get(t, -1)
            if module >= 0:
                sub = normalized[keys[module]]
                expected = (len(sub['inputs']), len(sub['outputs']))
            elif t in ('ROM', 'RAM'):
                aw = int(r.get('aw', 4))
                dw = int(r.get('dw', 8))
                expected = (aw + 1 if t == 'ROM' else aw + dw + 2, dw)
            else:
                expected = FIXED.get(t)
            if expected and (len(r['i']) > expected[0] or len(r['o']) > expected[1]):
                raise ValueError(f'{k}/{t}: too many ports, expected {expected}')
            if expected:
                r['i'] += [0] * (expected[0] - len(r['i']))
                r['o'] += [0] * (expected[1] - len(r['o']))

    out = []
    out.append('import model')
    out.append('')
    out.append('proc makeDesign*(): Design =')
    out.append('  var d: Design')
    out.append(f'  d.name = {nimstr(tables["workspace"].get("n", path.stem))}')
    out.append(f'  d.root = {ids["workspace"]}')
    out.append(f'  d.definitions = newSeq[Definition]({len(keys)})')
    for k in keys:
        rows = normalized[k]
        allrows = sum(rows.values(), [])
        maxwire = max([0] + [w for r in allrows for w in r['i'] + r['o']])
        out.append(f'  # --- {tables[k].get("n", k)} ---')
        out.append('  block:')
        out.append(f'    var m = addr d.definitions[{ids[k]}]')
        out.append(f'    m.name = {nimstr(tables[k].get("n", k))}')
        out.append(f'    m.nets = {maxwire}\'u32')
        out.append('    m.ins = ' + nim_seq_nets([r['o'][0] for r in rows['inputs']]))
        out.append('    m.outs = ' + nim_seq_nets([r['i'][0] for r in rows['outputs']]))
        out.append('    m.elements = @[')
        for r in allrows:
            module = name_to_id.get(r['t'], -1)
            out.append('      ' + emit_element(r, module) + ',')
        out.append('    ]')
    out.append('  return d')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('\n'.join(out) + '\n')
    print(f'{path} -> {output}')

def main():
    p = argparse.ArgumentParser()
    p.add_argument('input', type=pathlib.Path)
    p.add_argument('output', type=pathlib.Path)
    a = p.parse_args()
    try: compile_file(a.input, a.output)
    except (ValueError, OSError, KeyError, TypeError) as e:
        sys.exit(f'lc_compile_nim: {e}\n')

if __name__ == '__main__':
    main()
