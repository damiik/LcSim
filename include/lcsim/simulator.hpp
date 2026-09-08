#pragma once
#include "model.hpp"
#include <deque>
#include <functional>
#include <map>
#include <queue>
#include <unordered_map>
namespace lc  {
  struct Probe  {
    std::string name;
    std::vector<Net> nets;
    std::vector<int> drivers;
    Element visual;
    bool input=false;
  };
  struct Transition  {
    Time time;
    Net net;
    Logic value;
  };
  struct Stats  {
    uint64_t events=0,evaluations=0,hits=0,misses=0,cache_bytes=0,invalid_writes=0;
  };
  struct MemoryInfo  {
    std::string name,type;
    uint32_t address_width=0,data_width=0;
    size_t words=0;
  };
  class Simulator  {
    public:
    explicit Simulator(const Design&,Profile=Profile::lvc(),bool use_cache=true);
    void advance(Time duration);
    void step()  {
      advance(profile.tick);
    }
    void drive(const std::string&,const std::string& value);
    Logic value(Net n) const  {
      return nets.at(n).value;
    }
    std::string bits(const Probe&) const;
    std::string hex(const Probe&) const;
    const std::vector<Probe>& probes() const  {
      return views;
    }
    const Probe* find(const std::string&) const;
    std::vector<std::pair<std::string,std::vector<uint64_t>>> memories() const;
    std::vector<MemoryInfo> memory_info() const;
    std::vector<uint64_t> memory_data(const std::string&) const;
    uint64_t memory_word(const std::string&,size_t address) const;
    void replace_memory(const std::string&,const std::vector<uint64_t>&);
    void clear_memory(const std::string& name)  {
      replace_memory(name,{});
    }
    std::string diagnostics() const;
    Time now=0;
    Profile profile;
    Stats stats;
    bool cache_enabled=true, auto_clock=true;
    size_t cache_budget=16*1024*1024;
    std::function<void(Transition)> observe;
    size_t gate_count() const  {
      return gates.size();
    }
    size_t net_count() const  {
      return nets.size();
    }
    private:
    struct Driver  {
      Net net;
      Logic value=Logic::Z,target=Logic::Z;
      bool weak=false,pending=false;
      uint64_t generation=0;
      bool target_weak=false;
    };
    struct Wire  {
      Logic value=Logic::Z;
      bool weak=false;
      std::vector<int> drivers,users;
    };
    struct Gate  {
      Element e;
      std::string path;
      std::vector<int> drivers;
      Logic stored=Logic::L,last_clock=Logic::L,last_data=Logic::X;
      Time data_changed=-1000000000,edge=-1000000000;
      int64_t address=-2,settled_address=-2;
      uint64_t read_word=0;
      bool ready=false;
      uint64_t read_generation=0;
      Logic switch_state=Logic::H;
    };
    struct Group  {
      int definition;
      std::vector<int> gates,children;
      bool pure=true;
    };
    struct Event  {
      Time at;
      uint64_t sequence;
      int kind,id;
      Logic value;
      uint64_t generation;
      bool weak=false;
      bool operator<(const Event& o) const  {
        return at!=o.at?at>o.at:sequence>o.sequence;
      }
    };
    struct Result  {
      int index;
      std::vector<Logic> values;
    };
    struct Cache  {
      std::unordered_map<std::string,std::vector<Result>> entries;
    };
    std::vector<Wire> nets;
    std::vector<Driver> drivers;
    std::vector<Gate> gates;
    std::vector<Group> groups;
    std::vector<Cache> caches;
    std::vector<Probe> views;
    std::vector<Net> parent;
    std::priority_queue<Event> queue;
    uint64_t sequence=0;
    std::vector<bool> dirty;
    int root_group=0;
    bool has_switches=false,initializing=true;
    std::vector<Net> touched;
    Net alloc();
    Net root(Net);
    void join(Net,Net);
    int flatten(const Design&,int,const std::vector<Net>&,const std::vector<Net>&,const std::string&,bool);
    void resolve();
    void evaluate_dirty();
    void evaluate_group(int,const std::vector<bool>&);
    std::vector<Logic> evaluate_pure(const Gate&);
    void evaluate_stateful(int);
    void apply(int,const std::vector<Logic>&);
    void schedule(int,Logic,Time,bool weak=false);
    Time delay(const Gate&) const;
    void enqueue(Time,int,int,Logic=Logic::X,uint64_t=0,bool weak=false);
    std::vector<Logic> inputs(const Gate&) const;
  };
}
