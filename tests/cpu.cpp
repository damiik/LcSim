#include <lcsim/simulator.hpp>
#include <chrono>
#include <iostream>
#include <stdexcept>
using namespace lc;
int main()  {
  auto design=make_design();
  for(auto profile:  {
    Profile::lvc(),Profile::fpga()
  }
  )  {
    uint64_t reference=0;
    for(bool cache:  {
      false,true
    }
    )  {
      Simulator sim(design,profile,cache);
      uint64_t hash=1469598103934665603ULL;
      sim.observe=[&](Transition t)  {
        for(uint64_t n:  {
          uint64_t(t.time),uint64_t(t.net),uint64_t(t.value)
        }
        )  {
          hash^=n;
          hash*=1099511628211ULL;
        }
      };
      auto start=std::chrono::steady_clock::now();
      for(int i=0; i<18000; i++)sim.step();
      auto memories=sim.memories();
      if(memories.size()!=2)throw std::runtime_error("CPU stack-lab must expose main and stack RAM");
      const auto& memory=memories.at(0).second;
      for(auto [a,v]:std::vector<std::pair<int,int>>  {
        {
          3,0x99
        },  {
          4,0x42
        },  {
          5,0xff
        },  {
          6,0xff
        },  {
          7,0x7e
        },  {
          8,0x55
        }
      })if(memory.at(a)!=uint64_t(v))throw std::runtime_error("CPU stack-lab main RAM mismatch "+profile.name+" at "+std::to_string(a));
      const auto& stack=memories.at(1).second;
      for(auto [a,v]:std::vector<std::pair<int,int>>  {
        {0x00,0x7e},{0xfe,0x99},{0xff,0x55}
      })if(stack.at(a)!=uint64_t(v))throw std::runtime_error("CPU stack-lab stack RAM mismatch "+profile.name+" at "+std::to_string(a));
      auto pc=sim.find("PC_ADR.PC");
      if(!pc||(sim.hex(*pc)!="0x2A"&&sim.hex(*pc)!="0x2B"))throw std::runtime_error("CPU stack-lab did not reach done loop");
      auto stack_pointer=sim.find("S");
      if(!stack_pointer||sim.hex(*stack_pointer)!="0x00")throw std::runtime_error("CPU stack pointer did not wrap back to $00");
      if(cache&&hash!=reference)throw std::runtime_error("CPU cache changed trace");
      reference=hash;
      double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
      std::cout<<profile.name<<" cache="<<cache<<" steps/s="<<18000/elapsed<<" hits="<<sim.stats.hits<<" misses="<<sim.stats.misses<<" bytes="<<sim.stats.cache_bytes<<" hash="<<hash<<" stack instructions/wrap OK\n";
    }
  }
}
