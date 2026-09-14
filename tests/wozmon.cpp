#include <lcsim/simulator.hpp>
#include <iostream>
#include <stdexcept>
using namespace lc;
int main(int argc,char**argv){
 const auto profile=argc>1&&std::string(argv[1])=="fpga"?Profile::fpga():Profile::lvc();
 bool cache=argc<3||std::string(argv[2])!="0";
 Simulator s(make_design(),profile,cache);auto dev=s.terminals().at(0);auto& tty=*dev.second;
 const std::string script="0400: 41 42\r0400.0401\r0500: A9 21 8D 00 50 4C 00 FF\r0500r\r";
 if(!s.terminal_send(dev.first,script))throw std::runtime_error("keyboard queue");
 int tick=0;bool done=false;
 for(;tick<1000000;tick++){
  if(tick&&tick%200000==0)
   std::cerr<<profile.name<<" cache="<<cache<<" ticks="<<tick
            <<" queued="<<tty.keys.size()<<std::endl;
  s.step();if(tick%100==0&&tty.keys.empty()&&tty.transcript.find("!\\\n")!=std::string::npos){done=true;break;}
 }
 std::cout<<tty.transcript<<std::endl;
 if(!done||s.memory_word("MainRAM",0x400)!=0x41||s.memory_word("MainRAM",0x401)!=0x42)
  throw std::runtime_error("WozMon store/read/run failed; PC="+s.hex(*s.find("PC_ADR.PC")));
 if(tty.transcript.find("0400.0401\n\n0400: 41 42")==std::string::npos)
  throw std::runtime_error("missing examine response");
 std::cout<<profile.name<<" cache="<<cache<<" ticks="<<tick<<" ACIA WozMon store/range/run/return PASS"<<std::endl;
}
