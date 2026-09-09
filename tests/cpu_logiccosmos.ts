// Optional integration test against a separate LogicCosmos TypeScript checkout.
// From that checkout: node --import tsx /path/LcSim/tests/cpu_logiccosmos.ts .
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
async function main() {
  const cosmos=path.resolve(process.argv[2]||'.');
  const load=(relative:string)=>import(pathToFileURL(path.join(cosmos,relative)).href);
  const {parseFromToml}=await load('src/io/toml_helper.ts');
  const {PhysicalSimulator}=await load('src/simulator/simulator_physical.ts');
  const {parseMemoryWords}=await load('src/simulator/special_nodes.ts');
  const {collectStrongSignalConflicts}=await load('src/app/simulation/SignalConflictTracing.ts');
  const source=fs.readFileSync(process.argv[3] || path.resolve(path.dirname(process.argv[1]),'../examples/cpu65c02.toml'),'utf8');
  for(const technology of ['lvc','fpga']) {
    const parsed=parseFromToml(source),sim=new PhysicalSimulator();
    sim.nodes=parsed.workspaceNodes;sim.wires=parsed.workspaceWires;sim.customModules=parsed.customModules;
    const control=sim.nodes.find((n:any)=>n.type==='ROM'&&n.dataWidth===45);
    assert.equal(parseMemoryWords(control.memoryContents)[3*256+0xa0],0x106180099773n,'LDY word radix');
    const rom=sim.nodes.find((n:any)=>n.name==='ProgramROM');
    assert.equal(parseMemoryWords(rom.memoryContents)[3],0x20n,'JSR opcode radix');
    sim.setGateTechnology(technology);sim.compute(false);
    let revision=sim.getConflictRevision();
    for(let n=0;n<20000;n++) {
      sim.compute(true,false);
      const current=sim.getConflictRevision();
      if(current!==revision) {
        sim.publishSimulationState();
        const conflicts=collectStrongSignalConflicts(sim.nodes,sim.wires);
        assert.equal(conflicts.length,0,technology+' conflict at tick '+n+': '+JSON.stringify(conflicts));
        revision=current;
      }
    }
    sim.publishSimulationState();
    const ram=parseMemoryWords(sim.nodes.find((n:any)=>n.name==='MainRAM').memoryContents);
    for(const [a,v] of [[0x1fb,5],[0x1fc,0xf5],[0x1fd,0xaa],[0x1fe,0],[0x1ff,0xf1],
                        [0x200,0x42],[0x201,0x7f],[0x202,0x33],[0x2f0,0xff],[0x2f1,0],
                        [0x300,0x99],[0xffe,0x55],[0xfff,0xa5]])assert.equal(ram[a],BigInt(v),technology+' RAM '+a.toString(16));
    const word=(prefix:string,width:number)=>Array.from({length:width},(_,i)=>{
      const state=sim.nodes.find((n:any)=>n.name===prefix+i).outputStates[0];
      assert.ok(!state.isFloating&&!state.isConflict&&state.level!=='X',prefix+i);
      return Number(state.level)*2**i;
    }).reduce((a,b)=>a+b,0);
    assert.ok([0xf180,0xf181].includes(word('PC_ADR.PC',16)));
    assert.equal(word('S.D',8),0xff);
    console.log(technology+': LogicCosmos CPU r8 absolute/JSR/RTS signature and conflict checks OK');
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
