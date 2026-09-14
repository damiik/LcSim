#!/usr/bin/env python3
"""Upgrade the r10/r11 CPU to BIT, abs,Y and indirect addressing, preserving layout."""
import argparse,json,tomllib
from pathlib import Path
from cpu65c02_image import hex_words

def upgrade(text,control):
 d=tomllib.loads(text);table=d['workspace'];g=[];prev={};new=[];patch={}
 for raw in table['gates']:
  prev.update({k:raw[k] for k in table['inherit'] if k in raw});g.append({**prev,**raw})
 if any(r.get('n')=='PTR_LOAD' for r in g):raise ValueError('CPU already upgraded')
 def wires(v):
  if isinstance(v,int):return [v]
  if isinstance(v,list):return [w for x in v for w in wires(x)]
  return []
 wire=max(w for section in ['inputs','gates','outputs'] for r in table.get(section,[]) for k in ['i','o'] for w in wires(r.get(k)))+1
 def alloc(n=1):
  nonlocal wire
  out=list(range(wire,wire+n));wire+=n;return out[0] if n==1 else out
 def gate(t,i,o=None,x=3200,y=1600,**kw):
  if o is None:o=alloc()
  new.append(dict(t=t,i=i,o=o,x=x,y=y,cd='',nnp='CENTER',**kw));return o
 def node(name,x,y,i=0):return gate('NODE',i,x=x,y=y,n=name)
 def bus(prefix,x,y):return [node(prefix+str(j),x,y+20*j) for j in range(8)]
 def change(idx,**kw):patch[idx]={**g[idx],**kw}
 def require(idx,t):
  if g[idx]['t']!=t:raise ValueError(f'unsupported base layout at gate {idx}, expected {t}')
 require(8,'ROM');require(534,'ADDR_ADD8')
 if g[8].get('dw')!=45:raise ValueError('expected r8+ 45-bit control ROM')
 if len(control)!=4096 or any(not 0<=v<1<<50 for v in control):raise ValueError('expected 4096 x 50-bit r12 control image')
 flags=alloc(5)
 signals=['PTR_LOAD','MAR_PTR_NEXT','PTR_ZP','MAR_ABSY','FLAGS_BIT']
 for j,name in enumerate(signals):node(name,-340,660+20*j,flags[j])
 change(8,dw=50,o=g[8]['o']+flags,m=' '.join(f'0x{v:013X}' for v in control+[0x10600009F7F1]*4096),cd='Control: A0..7 IR, A8..11 STEP, A12 BOOT; r12 50 bits')
 lo=gate('L',[],x=3100,y=1500);hi=gate('H',[],x=3180,y=1500)
 # A stable pointer snapshot is taken during target-low read, before MAR advances.
 clock=node('PHI2',3000,1660);load=node('PTR_LOAD',3000,1700)
 pointer=[]
 for bank in range(2):
  values=[node('MAR.A'+str(bank*8+j),3000,1760+bank*320+j*20) for j in range(8)]
  out=alloc(8);gate('ADDRESS_HIGH8',[clock,load]+values,out,x=3240,y=1860+bank*320,n='Pointer snapshot '+str(bank));pointer+=out
  for j,v in enumerate(out):node('PTR.A'+str(bank*8+j),3400,1760+bank*320+j*20,v)
 # Add one, carrying into high byte only for absolute indirect JMP.
 low_sum=alloc(9);gate('ADDR_ADD8',pointer[:8]+[lo]*8+[hi],low_sum,x=3600,y=1780,n='Pointer increment low')
 high_sum=alloc(9);gate('ADDR_ADD8',pointer[8:]+[lo]*8+[low_sum[8]],high_sum,x=3600,y=2180,n='Pointer increment high')
 wrap=node('PTR_ZP',3500,2480)
 next_hi=[gate('MUX2',[v,lo,wrap],x=3840,y=2100+j*60) for j,v in enumerate(high_sum[:8])]
 next_address=low_sum[:8]+next_hi
 # abs,Y uses existing EA low sum and adds its carry to ADH.
 abs_low=g[534]['o'][:8];carry=g[534]['o'][8]
 abs_high=alloc(9);gate('ADDR_ADD8',bus('ADH.D',3000,2600)+[lo]*8+[carry],abs_high,x=3240,y=2720,n='Absolute indexed high')
 indexed=abs_low+abs_high[:8]
 # Insert dedicated sources directly before the existing clocked MAR bit cells.
 for bit,idx in enumerate(list(range(637,645))+list(range(811,840,4))):
  require(idx,'DFF');old=g[idx]['i']
  expected_q=861+2*bit if bit<8 else 1089+5*(bit-8)
  if g[idx]['o'][0]!=expected_q:raise ValueError('unsupported MAR row ordering')
  sy=node('MAR_ABSY',3500,2820+bit*80);sn=node('MAR_PTR_NEXT',3500,2840+bit*80)
  value=gate('MUX2',[old[1],indexed[bit],sy],x=3660,y=2820+bit*80)
  value=gate('MUX2',[value,next_address[bit],sn],x=3820,y=2820+bit*80)
  change(idx,i=[old[0],value])
 # Suppress C writes whenever PRES_C is active (BIT, loads and logic ops).
 # A clock enable avoids a transient conflict in the old tri-state feedback.
 bit_active=node('FLAGS_PRES_C',700,1120)
 bit_inactive=gate('NOT',bit_active,x=780,y=1120)
 carry_clock=gate('AND',[g[588]['i'][0],bit_inactive],x=860,y=1160)
 change(588,i=[carry_clock]+g[588]['i'][1:])
 # BIT preserves A and C; Z is computed by AND while N/V come from operand bits.
 for idx,bit in [(593,6),(598,7)]:
  require(idx,'FLAG_CELL');old=g[idx]['i'];x=g[idx]['x'];y=g[idx]['y']
  value=gate('MUX2',[old[1],node('TMP.D'+str(bit),x-180,y-160),node('FLAGS_BIT',x-180,y-120)],x=x-80,y=y-180)
  change(idx,i=[old[0],value]+old[2:])
 # Restore inherited fields after each changed row, so formatting changes do not
 # silently change the following original component.
 start=text.index('gates = [',text.index('[workspace]'));end=text.index('\n]',start)
 lines=text[start:end].splitlines();out=[lines[0]];idx=0
 inline=lambda r:'  {'+', '.join(k+' = '+json.dumps(v,ensure_ascii=False,separators=(',',':')) for k,v in r.items())+'},'
 for line in lines[1:]:
  if line.lstrip().startswith('{'):
   row=patch.get(idx)
   if row is None and idx-1 in patch and any(patch[idx-1].get(f)!=g[idx-1].get(f) for f in table['inherit']):row=g[idx]
   out.append(inline(row) if row else line);idx+=1
  else:out.append(line)
 out.extend(map(inline,new))
 return (text[:start]+'\n'.join(out)+text[end:]).rstrip()+'\n'

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('cpu',type=Path);p.add_argument('control',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.write_text(upgrade(a.cpu.read_text(),hex_words(a.control.read_text())))
if __name__=='__main__':main()
