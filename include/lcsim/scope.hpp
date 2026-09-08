#pragma once
#include "simulator.hpp"
#include <fstream>
namespace lc  {
  struct Sample  {
    Time time;
    std::string bits;
  };
  struct Channel  {
    Probe probe;
    std::deque<Sample> samples;
  };
  class Scope  {
    public:
    explicit Scope(Simulator&,const std::vector<std::string>& names=  {}
    );
    ~Scope();
    void record(Transition);
    void arm();
    void configure(const ScopeConfig&);
    bool has_channel(const std::string&) const;
    bool add_channel(const std::string&);
    bool remove_channel(size_t);
    bool move_channel(size_t,int direction);
    void poll(Time t);
    void export_vcd(const std::string&,Time begin,Time end)const;
    void export_csv(const std::string&,Time begin,Time end)const;
    std::string at(size_t channel,Time)const;
    std::vector<Channel> channels;
    size_t capacity=4096;
    // transitions per channel, bounded RLE
    enum Mode  {
      Auto,Normal,Single
    };
    Mode mode=Auto;
    int trigger_channel=-1,trigger_bit=0;
    bool rising=true,both_edges=false;
    std::string trigger_value;
    Time span=1000000,holdoff=0,trigger_time=-1;
    double pretrigger=0.3;
    bool frozen=false;
    Time available_begin()const;
    private:
    Simulator& sim;
    std::unordered_map<Net,std::vector<size_t>> listeners;
    const Probe* resolve_probe(const std::string&) const;
    void rebuild_listeners();
    Time capture_end=-1,next_trigger=0;
  };
}
