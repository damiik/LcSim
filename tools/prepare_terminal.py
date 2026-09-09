#!/usr/bin/env python3
"""Create an LcSim terminal CPU from an existing r8+ schematic and a 4 KiB ROM."""
import argparse,json,tomllib
from pathlib import Path
from cpu65c02_image import update,hex_words

def prepare(source,program):
    text=update(source,program=program)
    d=tomllib.loads(text);gates=d['workspace']['gates'];prev={};nodes={};highest=0
    def wires(v):
        if isinstance(v,int):return [v]
        if isinstance(v,list):return [n for x in v for n in wires(x)]
        return []
    for section in ('inputs','gates','outputs'):
        for row in d['workspace'].get(section,[]):
            highest=max([highest]+wires(row.get('i'))+wires(row.get('o')))
    for raw in gates:
        prev.update({k:raw[k] for k in d['workspace'].get('inherit',[]) if k in raw})
        row={**prev,**raw}
        if row.get('t')=='TERMINAL':raise ValueError('source already contains a terminal')
        if row.get('t')=='NODE' and row.get('n'):nodes[row['n']]=wires(row['o'])[0]
    names=[f'MEM.A{i}' for i in range(16)]+[f'DATA.D{i}' for i in range(8)]+['RAW.MEM_OE_N','MEM_WE_EN']
    for name in names:
        if name not in nodes:raise ValueError('missing signal '+name)
    outputs=list(range(highest+1,highest+9))
    rows=[dict(t='TERMINAL',n='Console',i=[nodes[n] for n in names],o=outputs,io_base=0xd010,x=3000,y=1100,cd='Apple-1-style polling console',nnp='CENTER')]
    rows += [dict(t='NODE',n=f'DATA.D{i}',i=w,o=highest+9+i,x=3160,y=1060+20*i,cd='',nnp='CENTER') for i,w in enumerate(outputs)]
    start=text.index('gates = [',text.index('[workspace]'));end=text.index('\n]',start)
    inline=lambda r:'  {'+', '.join(k+' = '+json.dumps(v,separators=(',',':')) for k,v in r.items())+'},'
    return (text[:end]+'\n'+'\n'.join(map(inline,rows))+text[end:]).rstrip()+'\n'

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('cpu',type=Path);p.add_argument('rom',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    a.output.write_text(prepare(a.cpu.read_text(),hex_words(a.rom.read_text())))
if __name__=='__main__':main()
