#pragma once
#include "model.hpp"
#include "terminal.hpp"
#include <memory>
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
      return nets[n].value;
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
    std::vector<std::pair<std::string,Terminal*>> terminals();
    bool terminal_send(const std::string&,const std::string&);
    std::string diagnostics() const;
    Time now=0;
    Profile profile;
    Stats stats;
    bool cache_enabled=true, auto_clock=true;
    size_t cache_budget=16*1024*1024;
    std::function<void(Transition)> observe;
    std::vector<uint8_t> observed;
    size_t gate_count() const  {
      return gates.size();
    }
    size_t net_count() const  {
      return nets.size();
    }
    void observe_net(Net n,bool on)  {
      if(n<observed.size())observed[n]=on?1:0;
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
      std::unique_ptr<Terminal> terminal;
      bool terminal_key_latched=false;
      bool terminal_read=false,terminal_write=false,terminal_write_valid=false;
      int terminal_reg=-1,terminal_write_reg=-1;
      uint8_t terminal_read_value=0,terminal_write_value=0;
      std::string path;
      std::vector<int> drivers;
      Logic stored=Logic::L,last_clock=Logic::L,last_data=Logic::X;
      Time data_changed=-1000000000,edge=-1000000000;
      int64_t address=-2,settled_address=-2;
      uint64_t read_word=0;
      bool ready=false;
      uint64_t read_generation=0;
      Logic switch_state=Logic::H;
      Logic last_q=Logic::Z,last_nq=Logic::Z;
      Time delay_ps=0, period_ps=0, memory_delay_ps=0;
      bool fast_clock=false;
    };
    struct Group  {
      int definition;
      std::vector<int> gates,direct,children;
      uint32_t dirty=0;
      bool pure=true;
    };
    struct Event  {
      uint64_t generation;
      int32_t id;
      uint8_t kind;
      Logic value;
      bool weak=false;
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
    std::unordered_map<std::string,size_t> probe_index;
    std::vector<Net> parent;
     struct Bucket {
      Time at=0;
      std::vector<Event> events;
    };
    std::vector<Bucket> buckets;
    size_t bucket_head=0;
    std::vector<uint8_t> dirty;
    std::vector<int> dirty_gates,dirty_groups;
    std::vector<std::vector<int>> gate_groups;
    int root_group=0;
    bool has_switches=false,initializing=true;
    std::vector<Net> touched;
    std::vector<uint8_t> touched_flag;
    std::vector<Net> touched_list;
    Net alloc();
    Net root(Net);
    void join(Net,Net);
    int flatten(const Design&,int,const std::vector<Net>&,const std::vector<Net>&,const std::string&,bool);
    void resolve();
    void mark_dirty(int);
    void evaluate_dirty();
    void evaluate_group(int,const std::vector<uint8_t>&);
    void evaluate_pure(int);
    void evaluate_stateful(int);
    void schedule(int,Logic,Time,bool weak=false);
    Time delay(const Gate&) const;
    void enqueue(Time,int,int,Logic=Logic::X,uint64_t=0,bool weak=false);
  };
}
