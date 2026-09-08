#include <lcsim/scope.hpp>
#ifdef LCSIM_GUI
#include <lcsim/gui.hpp>
#endif
#include <chrono>
#include <iostream>
#include <stdexcept>
int main(int argc,char** argv)  {
  try  {
    lc::Profile profile=lc::Profile::lvc();
    uint64_t steps=10000;
    bool headless=false,scope=false,cache=true,dump=false;
    std::string vcd;
    std::vector<std::pair<std::string,std::string>> inputs;
#ifdef LCSIM_SCOPE
    scope=true;
#endif
    for(int i=1; i<argc; i++)  {
      std::string a=argv[i];
      auto arg=[&]()  {
        if(i+1>=argc)throw std::runtime_error("missing value for "+a);
        return std::string(argv[++i]);
      };
      if(a=="--dump")dump=true;
      else if(a=="--technology")  {
        auto t=arg();
        if(t!="fpga"&&t!="lvc")throw std::runtime_error("technology must be fpga or lvc");
        profile=t=="fpga"?lc::Profile::fpga():lc::Profile::lvc();
      }
      else if(a=="--headless")headless=true;
      else if(a=="--scope")scope=true;
      else if(a=="--no-cache")cache=false;
      else if(a=="--steps")steps=std::stoull(arg());
      else if(a=="--vcd")vcd=arg();
      else if(a=="--input")  {
        auto text=arg();
        auto pos=text.find('=');
        if(pos==std::string::npos)throw std::runtime_error("expected --input NAME=VALUE");
        inputs.push_back(  {
          text.substr(0,pos),text.substr(pos+1)
        }
        );
      }
      else if(a=="--help")  {
        std::cout<<"LcSim: [--headless] [--scope] [--technology fpga|lvc] [--steps N] [--no-cache] [--vcd FILE] [--input NAME=VALUE]\n";
        return 0;
      }
      else throw std::runtime_error("unknown option "+a);
    }
    auto design=lc::make_design();
#ifdef LCSIM_GUI
    if(!headless)return lc::gui(design,profile,scope,cache);
#else
    (void)headless;
    (void)scope;
#endif
    lc::Simulator sim(design,profile,cache);
    lc::Scope analyzer(sim,design.scope);
    analyzer.configure(design.scope_config);
    for(const auto& [n,v]:inputs)sim.drive(n,v);
    auto start=std::chrono::steady_clock::now();
    for(uint64_t i=0; i<steps; i++)sim.step();
    double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    std::cout<<"technology="<<profile.name<<" time_ps="<<sim.now<<" gates="<<sim.gate_count()<<" nets="<<sim.net_count()<<" steps_per_second="<<steps/seconds<<" cache_hits="<<sim.stats.hits<<" cache_misses="<<sim.stats.misses<<" cache_bytes="<<sim.stats.cache_bytes<<" invalid_writes="<<sim.stats.invalid_writes<<'\n';
    for(const auto& p:sim.probes())std::cout<<p.name<<'='<<sim.hex(p)<<'\n';
    for(const auto& [name,memory]:sim.memories())  {
      std::cout<<"RAM "<<name<<':'<<std::hex;
      for(auto word:memory)std::cout<<' '<<word;
      std::cout<<std::dec<<'\n';
    }
    if(dump)std::cout<<sim.diagnostics();
    if(!vcd.empty())analyzer.export_vcd(vcd,analyzer.available_begin(),sim.now);
    return 0;
  }
  catch(const std::exception& e)  {
    std::cerr<<"LcSim: "<<e.what()<<'\n';
    return 1;
  }
}
