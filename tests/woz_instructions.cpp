#include <lcsim/simulator.hpp>
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace lc;
int main(){
 auto d=make_design();std::ifstream file("examples/cpu65c02-woz-instructions.hex");std::vector<uint64_t> rom;std::string token;
 while(file>>token)rom.push_back(std::stoull(token,nullptr,16));
 if(rom.size()!=4096)throw std::runtime_error("bad ROM image");
 for(auto& e:d.definitions[d.root].elements)if(e.name=="ProgramROM")e.memory=rom;
 for(auto profile:{Profile::lvc(),Profile::fpga()})for(bool cache:{false,true}){
  Simulator s(d,profile,cache);for(int i=0;i<50000;i++)s.step();
  if(s.memory_word("MainRAM",0x800)!=0xa5||s.memory_word("MainRAM",0x8ff)!=0)
   throw std::runtime_error(profile.name+" instruction test failed: PC="+s.hex(*s.find("PC_ADR.PC"))+" A="+s.hex(*s.find("A_OUT.D")));
  std::cout<<profile.name<<" cache="<<cache<<" BIT/abs,Y/(zp,X)/JMP indirect boundary tests PASS"<<std::endl;
 }
}
