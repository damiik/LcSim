#include <lcsim/scope.hpp>
#include <iostream>
#include <stdexcept>
using namespace lc;
void check(bool condition,const char* message){if(!condition)throw std::runtime_error(message);}
Element el(std::string type,std::vector<Net> in,std::vector<Net> out,std::string name=""){Element e;e.type=type;e.in=in;e.out=out;e.name=name;return e;}
Design design(std::vector<Element> elements){Definition m;m.nets=40;m.elements=elements;Design d;d.definitions.push_back(m);return d;}
Logic get(Simulator& s,const char* name){return s.value(s.find(name)->nets[0]);}
int main(){
 for(int count:{2,4}){
  std::vector<Element> elements;
  for(int bit=0;bit<count+2;bit++)elements.push_back(el("INPUT",{},{Net(bit+1)},"I"+std::to_string(bit)));
  std::vector<Net> inputs;for(int bit=0;bit<count+(count==4?2:1);bit++)inputs.push_back(Net(bit+1));
  elements.push_back(el(count==4?"MUX4":"MUX2",inputs,{20}));elements.push_back(el("OUTPUT",{20},{},"Q"));Simulator sim(design(elements));
  for(int word=0;word<(1<<count);word++)for(int sel=0;sel<count;sel++){
   for(int bit=0;bit<count;bit++)sim.drive("I"+std::to_string(bit),(word>>bit)&1?"1":"0");
   sim.drive("I"+std::to_string(count),sel&1?"1":"0");if(count==4)sim.drive("I5",sel&2?"1":"0");sim.advance(10000);check(get(sim,"Q")==((word>>sel)&1?Logic::H:Logic::L),"MUX truth table");
  }
  std::vector<Element> dem{el("INPUT",{},{1},"D"),el("INPUT",{},{2},"A"),el("INPUT",{},{3},"B")};std::vector<Net> outs;for(int i=0;i<count;i++){outs.push_back(Net(10+i));dem.push_back(el("OUTPUT",{Net(10+i)},{},"Q"+std::to_string(i)));}dem.push_back(el(count==4?"DMUX4":"DMUX2",count==4?std::vector<Net>{1,2,3}:std::vector<Net>{1,2},outs));Simulator ds(design(dem));
  for(int sel=0;sel<count;sel++){ds.drive("A",sel&1?"1":"0");ds.drive("B",sel&2?"1":"0");ds.advance(10000);for(int bit=0;bit<count;bit++)check(get(ds,("Q"+std::to_string(bit)).c_str())==(bit==sel?Logic::H:Logic::L),"DMUX address order");}
 }
 auto ram=el("RAM",{1,2,3,4,5,6},{7,8});ram.aw=2;ram.dw=2;ram.memory_ns=5;ram.memory={1,2,3,0};
 Simulator memory(design({el("INPUT",{},{1},"A0"),el("INPUT",{},{2},"A1"),el("INPUT",{},{3},"D0"),el("INPUT",{},{4},"D1"),el("INPUT",{},{5},"WE"),el("INPUT",{},{6},"OE"),ram,el("OUTPUT",{7},{},"Q0"),el("OUTPUT",{8},{},"Q1")}));
 memory.drive("A0","0");memory.drive("A1","0");memory.drive("OE","0");memory.advance(5000);check(get(memory,"Q0")==Logic::H,"RAM address settle");memory.drive("A0","1");memory.advance(4999);check(get(memory,"Q0")==Logic::H,"RAM must retain previous word during address delay");memory.advance(1);check(get(memory,"Q1")==Logic::H&&get(memory,"Q0")==Logic::L,"RAM new word");memory.drive("OE","1");check(get(memory,"Q0")==Logic::Z,"OE should be immediate");memory.drive("D0","X");memory.drive("WE","0");check(memory.memories()[0].second[1]==2&&memory.stats.invalid_writes>0,"invalid write corrupted RAM");
 auto memory_info=memory.memory_info();check(memory_info.size()==1&&memory_info[0].type=="RAM"&&memory_info[0].words==4,"memory browser metadata");memory.replace_memory(memory_info[0].name,{3,0});check(memory.memory_word(memory_info[0].name,0)==3&&memory.memory_data(memory_info[0].name)==std::vector<uint64_t>({3,0,0,0}),"memory paste/browser");memory.clear_memory(memory_info[0].name);check(memory.memory_data(memory_info[0].name)==std::vector<uint64_t>({0,0,0,0}),"memory clear");
 auto rom=el("ROM",{1,2,3},{4,5});rom.aw=2;rom.dw=2;rom.memory={0,1,2,3};Simulator readonly_memory(design({el("INPUT",{},{1},"A0"),el("INPUT",{},{2},"A1"),el("INPUT",{},{3},"OE"),rom,el("OUTPUT",{4},{},"Q0"),el("OUTPUT",{5},{},"Q1")}));auto rom_info=readonly_memory.memory_info();check(rom_info.size()==1&&rom_info[0].type=="ROM","ROM browser metadata");readonly_memory.replace_memory(rom_info[0].name,{3});check(readonly_memory.memory_data(rom_info[0].name)==std::vector<uint64_t>({3,0,0,0}),"ROM paste");
 Simulator weak(design({el("PULLUP",{},{1}),el("H",{},{2}),el("TBUF",{1,2},{3}),el("L",{},{3}),el("OUTPUT",{3},{},"Q")}));check(get(weak,"Q")==Logic::L,"TBUF must preserve weak strength");
 Simulator oc(design({el("INPUT",{},{1},"A"),el("OC",{1},{2}),el("PULLUP",{},{2}),el("OUTPUT",{2},{},"Q")}));check(get(oc,"Q")==Logic::L,"OC inverts");oc.drive("A","0");oc.advance(10000);check(get(oc,"Q")==Logic::H,"OC releases");
 Simulator source(design({el("INPUT",{},{1},"A")}));Scope scope(source,{"A"});scope.mode=Scope::Single;scope.trigger_channel=0;scope.span=10000;source.drive("A","0");source.advance(1000);source.drive("A","1");check(scope.trigger_time==1000,"scope trigger timestamp");source.advance(10000);scope.poll(source.now);check(scope.frozen,"single capture did not freeze without transitions");scope.arm();check(!scope.frozen,"arm");scope.capacity=2;for(int i=0;i<10;i++){source.advance(100);source.drive("A",i%2?"1":"0");}check(scope.channels[0].samples.size()<=2,"scope memory not bounded");
 std::cout<<"PASS: exhaustive MUX/DMUX, RAM timing/OE/invalid-write/editor, weak TBUF, OC, scope trigger/RLE bounds\n";
}
