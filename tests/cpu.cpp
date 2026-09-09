#include <lcsim/simulator.hpp>
#include <chrono>
#include <iostream>
#include <fstream>
#include <stdexcept>
using namespace lc;
namespace {
void require(bool ok,const std::string& message) { if(!ok) throw std::runtime_error(message); }
uint64_t word(Simulator& sim,const std::string& name) {
  auto p=sim.find(name); require(p!=nullptr,"Missing probe: "+name);
  uint64_t v=0;for(size_t i=0;i<p->nets.size();i++) {
    auto bit=sim.value(p->nets[i]);
    if(bit!=Logic::L && bit!=Logic::H) return UINT64_MAX;
    if(bit==Logic::H)v|=uint64_t(1)<<i;
  }return v;
}
Element& named(Design& d,const std::string& name) {
  for(auto& e:d.definitions.at(d.root).elements)if(e.name==name)return e;
  throw std::runtime_error("Missing device "+name);
}
std::vector<uint64_t> image(const std::string& path) {
  std::ifstream file(path); require(bool(file),"Cannot read "+path);
  std::vector<uint64_t> result; std::string token;
  while(file>>token)result.push_back(std::stoull(token,nullptr,16));
  require(result.size()==4096,"Expected 4096-byte ROM");return result;
}
void steps(Simulator& sim,int n) { for(int i=0;i<n;i++)sim.step(); }
void signature(Simulator& sim) {
  auto memories=sim.memories();
  require(memories.size()==1,"CPU must have one unified RAM");
  const auto& ram=memories.at(0).second;
  require(ram.size()==4096,"RAM must be 4 KiB");
  for(auto [address,value]:std::vector<std::pair<int,int>> {
    {0x83,0x99},{0x84,0x42},{0x85,0xff},{0x86,0xff},{0x87,0x7e},
    {0x88,0x55},{0x89,0},{0x8a,0xa5},{0x100,0x7e},{0x1fe,0x99},{0x1ff,0x55}
  })require(ram.at(address)==uint64_t(value),sim.profile.name+" RAM mismatch at "+std::to_string(address));
  require(word(sim,"PC_ADR.PC")==0xf204 || word(sim,"PC_ADR.PC")==0xf205,"CPU did not reach F204 done loop");
  require(word(sim,"S.D")==0,"S did not wrap to 00");
  require(word(sim,"VECTOR.V")==0xf0d0,"PC start must come from both reset-vector bytes");
}
void absolute_signature(Simulator& sim) {
  for(auto [a,v]:std::vector<std::pair<int,int>> {
    {0x200,0x42},{0x201,0x7f},{0x202,0x33},{0x300,0x99},
    {0x2f0,0xff},{0x2f1,0},{0xffe,0x55},{0xfff,0xa5},
    {0x100,0xf0},{0x1ff,0xf1},{0x1fe,0},{0x1fd,0xaa},{0x1fc,0xf5},{0x1fb,5}
  })require(sim.memory_word("MainRAM",a)==uint64_t(v),sim.profile.name+" absolute/call RAM mismatch at "+std::to_string(a));
  auto pc=word(sim,"PC_ADR.PC");
  require(pc==0xf180 || pc==0xf181,"New program failed to reach F180");
  require(word(sim,"S.D")==0xff,"Calls did not restore S");
}
void absolute_test(const Design& design,Profile profile) {
  uint64_t reference=0;
  for(bool cache:{false,true}) {
    Simulator sim(design,profile,cache);
    uint64_t hash=1469598103934665603ULL;
    sim.observe=[&](Transition t) {
      for(uint64_t v:{uint64_t(t.time),uint64_t(t.net),uint64_t(t.value)}) {hash^=v;hash*=1099511628211ULL;}
    };
    bool step12=false,nested=false,boundary=false;
    for(int n=0;n<20000;n++) {
      sim.step();step12|=word(sim,"STEP.S")==12;
      nested|=word(sim,"PC_ADR.PC")==0xf600;
      boundary|=word(sim,"PC_ADR.PC")==0xf101;
    }
    absolute_signature(sim);
    require(step12 && nested && boundary,"Missing extended microstep / nested call / page return");
    if(cache)require(hash==reference,"Cache changed absolute/call transition trace");
    reference=hash;
    std::cout<<profile.name<<" cache="<<cache<<" absolute/JSR/RTS/stack wrap OK hash="<<hash<<std::endl;
  }
}
void boot_from_ram(const Design& original,Profile profile,bool cache,uint16_t start) {
  auto d=original;
  auto& rom=named(d,"ProgramROM").memory;
  rom[0xffc]=start&255;rom[0xffd]=start>>8;
  auto& ram=named(d,"MainRAM").memory;ram.assign(4096,0);
  // Execute actual CPU instructions in RAM. A marker in low RAM detects aliases.
  ram[0x23]=0x5a;
  std::vector<uint64_t> program={0xa9,0xc3,0x85,0x8b,0x80,0xfe};
  std::copy(program.begin(),program.end(),ram.begin()+start);
  Simulator sim(d,profile,cache);steps(sim,1800);
  require(sim.memory_word("MainRAM",0x8b)==0xc3,"RAM boot program did not run");
  require(sim.memory_word("MainRAM",0x23)==0x5a,"RAM high address aliases zero page");
  require(word(sim,"PC_ADR.PC")==uint64_t(start+4) || word(sim,"PC_ADR.PC")==uint64_t(start+5),"RAM boot PC has wrong high byte");
}
void wrap_pc(const Design& original,Profile profile,bool cache) {
  auto d=original;auto& rom=named(d,"ProgramROM").memory;
  // Reset at FFFE, NOP at FFFE/FFFF, then actual opcodes at RAM 0000.
  rom[0xffc]=0xfe;rom[0xffd]=0xff;rom[0xffe]=rom[0xfff]=0xea;
  named(d,"MainRAM").memory={0xa9,0x6d,0x85,0x8c,0x80,0xfe};
  Simulator sim(d,profile,cache);steps(sim,2200);
  require(sim.memory_word("MainRAM",0x8c)==0x6d,"PC failed FFFF -> 0000 rollover");
  require(word(sim,"PC_ADR.PC")==4 || word(sim,"PC_ADR.PC")==5,"16-bit PC rollover reached wrong address");
}
}
int main() {
  auto design=make_design();
  auto previous=design;
  named(previous,"ProgramROM").memory=image("examples/cpu65c02-memory16.hex");
  for(auto profile:{Profile::lvc(),Profile::fpga()}) {
    absolute_test(design,profile);
    uint64_t reference=0;
    for(bool cache:{false,true}) {
      Simulator sim(previous,profile,cache);
      uint64_t hash=1469598103934665603ULL;
      sim.observe=[&](Transition t) {
        for(uint64_t n:{uint64_t(t.time),uint64_t(t.net),uint64_t(t.value)}) {hash^=n;hash*=1099511628211ULL;}
      };
      auto start=std::chrono::steady_clock::now();
      bool low_vector=false,high_vector=false,passed_page=false,backward=false,forward=false;
      for(int i=0;i<20000;i++) {
        sim.step();auto pc=word(sim,"PC_ADR.PC"),addr=word(sim,"MEM.A");
        low_vector|=addr==0xfffc;high_vector|=addr==0xfffd;
        if(pc==0xf100)passed_page=true;
        if(passed_page && pc==0xf0fc)backward=true;
        if(pc==0xf200)forward=true;
      }
      signature(sim);
      require(low_vector && high_vector,"Boot did not read both reset addresses");
      require(backward && forward,"Signed branch did not cross a page in both directions");
      // Reset during normal execution re-reads a CHANGED vector, without clearing RAM.
      auto image=sim.memory_data("ProgramROM");
      std::vector<uint64_t> restart={0xa9,0xb6,0x85,0x8d,0x80,0xfe};
      std::copy(restart.begin(),restart.end(),image.begin()+0x320);
      image[0xffc]=0x20;image[0xffd]=0xf3;
      sim.drive("In_Reset","0");steps(sim,40);
      require(word(sim,"S.D")==0xff,"S reset raced its input mux");
      sim.replace_memory("ProgramROM",image);
      sim.drive("In_Reset","1");steps(sim,2000);
      require(sim.memory_word("MainRAM",0x8d)==0xb6,"Warm reset did not use new F320 vector");
      require(sim.memory_word("MainRAM",0x1ff)==0x55,"Warm reset cleared unified RAM");
      require(word(sim,"PC_ADR.PC")==0xf324 || word(sim,"PC_ADR.PC")==0xf325,"Warm reset stopped at wrong PC");
      if(cache)require(hash==reference,"Hierarchical cache changed CPU transition trace");
      reference=hash;
      boot_from_ram(design,profile,cache,0x0200);
      boot_from_ram(design,profile,cache,0x0f80);
      wrap_pc(design,profile,cache);
      double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
      std::cout<<profile.name<<" cache="<<cache<<" seconds="<<elapsed<<" hash="<<hash
               <<" PC16/MAR16/reset/stack/page branches/RAM boot/wrap OK\n";
    }
  }
}
