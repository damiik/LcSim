#include <lcsim/simulator.hpp>
#include <iostream>
#include <stdexcept>
using namespace lc;
void check(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
int main(){
 Terminal t;check(t.send("ab\r\n\b"),"queue");check(t.keys==std::deque<uint8_t>({0xc1,0xc2,0x8d,0xdf}),"keyboard encoding");
 auto before=t.keys;check(!t.send(std::string(Terminal::input_limit,'X'))&&t.keys==before,"overflow must reject entire paste");
 t.write(2,0xc1);check(t.transcript.empty(),"direction setup printed a character");t.write(3,0xa7);t.write(2,0xc1);t.write(2,0xdf);check(t.lines.back().empty(),"erase");
 for(size_t i=0;i<70000;i++)t.write(2,i%40?0xc1:0x8d);
 check(t.lines.size()<=Terminal::history_limit&&t.transcript.size()<=Terminal::transcript_limit,"unbounded terminal history");
 for(auto profile:{Profile::lvc(),Profile::fpga()})for(bool cache:{false,true}) {
  Definition m;m.nets=35;
  for(int i=0;i<26;i++){Element e;e.type="INPUT";e.name="I"+std::to_string(i);e.out={Net(i+1)};m.elements.push_back(e);}
  Element e;e.type="TERMINAL";e.name="TTY";for(int i=0;i<26;i++)e.in.push_back(i+1);for(int i=0;i<8;i++)e.out.push_back(27+i);m.elements.push_back(e);
  Design d;d.definitions.push_back(m);Simulator s(d,profile,cache);auto& tty=*s.terminals().at(0).second;
  auto pin=[&](int i,const char* value){s.drive("I"+std::to_string(i),value);};
  auto word=[&](int start,int count,unsigned value){for(int i=0;i<count;i++)pin(start+i,(value>>i)&1?"1":"0");};
  auto output=[&](){unsigned value=0;for(int i=0;i<8;i++){auto bit=s.value(27+i);check(bit==Logic::L||bit==Logic::H,"undefined terminal output");if(bit==Logic::H)value|=1<<i;}return value;};
  auto released=[&](){for(int i=0;i<8;i++)check(s.value(27+i)==Logic::Z,"unselected terminal drove bus");};
  auto write=[&](unsigned reg,unsigned data){word(0,16,0xd010+reg);word(16,8,data);pin(25,"0");s.advance(10000);pin(25,"1");};
  pin(24,"1");pin(25,"1");released();write(3,0xa7);
  word(0,16,0xd012);word(16,8,0xc1);pin(25,"0");word(16,8,0xc2);s.advance(10000);check(tty.transcript.empty(),"write committed before rising edge");pin(25,"1");check(tty.transcript=="B","write not committed exactly once with settled data");
  pin(25,"0");pin(16,"X");pin(25,"1");check(tty.transcript=="B","invalid data caused output");
  write(2,0xc3);check(tty.transcript=="BC","second write");
  word(0,16,0x4012);pin(24,"0");released();pin(24,"1");
  check(s.terminal_send("TTY","xy"),"runtime input");word(0,16,0xd011);pin(24,"0");check(output()&0x80,"keyboard ready");pin(24,"1");check(tty.keys.size()==2,"status consumed a key");
  word(0,16,0xd010);pin(24,"0");check(output()==0xd8,"keyboard byte");s.advance(10000);check(s.terminal_send("TTY","z"),"append while reading");check(output()==0xd8&&tty.keys.size()==3,"read was not held");pin(24,"1");check(tty.keys.size()==2,"read must consume once on release");released();
  pin(24,"0");check(output()==0xd9,"next key");pin(24,"1");pin(24,"0");check(output()==0xda,"last key");pin(24,"1");pin(24,"0");check(output()==0,"empty keyboard");pin(24,"1");
  word(0,16,0xd012);pin(24,"0");check(output()==0,"display must acknowledge immediately");pin(25,"0");released();
 }
 std::cout<<"PASS terminal encoding/bounds, MMIO select/read/write/Hi-Z in FPGA/LVC, cache on/off\n";
}
