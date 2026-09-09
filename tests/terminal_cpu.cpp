#include <lcsim/simulator.hpp>
#include <iostream>
#include <stdexcept>
using namespace lc;
void check(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
int main(){
 std::string reference;
 for(auto profile:{Profile::lvc(),Profile::fpga()})for(bool cache:{false,true}){
  Simulator s(make_design(),profile,cache);auto device=s.terminals().at(0);auto& terminal=*device.second;
  check(s.terminal_send(device.first,"0400: 41 42\r\n0400.0401\r0500: A9 21 8D 12 D0 4C 00 F8\r0500r\r"),"script queue");
  bool done=false;int ticks=0;
  for(;ticks<900000;ticks++){
   s.step();if(ticks%100==0&&terminal.keys.empty()&&terminal.transcript.find("!\\\n")!=std::string::npos){done=true;break;}
  }
  check(done,"monitor failed to execute RAM program and return to prompt");
  check(s.memory_word("MainRAM",0x400)==0x41&&s.memory_word("MainRAM",0x401)==0x42,"monitor RAM write");
  check(terminal.transcript.find("0400: 41\n0401: 42")!=std::string::npos,"monitor range read");
  if(reference.empty())reference=terminal.transcript;else check(reference==terminal.transcript,"terminal output differs with technology/cache");
  std::cout<<profile.name<<" cache="<<cache<<" ticks="<<ticks<<" monitor store/examine/range/run PASS"<<std::endl;
 }
}
