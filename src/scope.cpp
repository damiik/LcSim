#include <lcsim/scope.hpp>
#include <algorithm>
#include <set>
#include <stdexcept>
namespace lc  {
  Scope::Scope(Simulator& s,const std::vector<std::string>& names):sim(s)  {
    if(names.empty())  {
      for(const auto& p:s.probes())if(!p.visual.pixel&&channels.size()<64)add_channel(p.name);
    }
    else for(const auto& name:names)add_channel(name);
    rebuild_listeners();
    sim.observe=[this](Transition t)  {
      record(t);
    };
  }
  const Probe* Scope::resolve_probe(const std::string& name) const  {
    if(const auto* p=sim.find(name))return p;
    for(const auto& candidate:sim.probes())  {
      auto dot=candidate.name.rfind('.');
      if(dot!=std::string::npos&&candidate.name.substr(0,dot)==name&&candidate.nets.size()>1)return &candidate;
    }
    return nullptr;
  }
  void Scope::rebuild_listeners()  {
    listeners.clear();
    for(size_t c=0; c<channels.size(); c++)for(Net n:channels[c].probe.nets)listeners[n].push_back(c);
    if(trigger_channel>=static_cast<int>(channels.size()))trigger_channel=-1;
  }
  bool Scope::has_channel(const std::string& name) const  {
    return std::any_of(channels.begin(),channels.end(),[&](const Channel& c){return c.probe.name==name;});
  }
  bool Scope::add_channel(const std::string& name)  {
    const auto* p=resolve_probe(name);
    if(!p||p->visual.pixel||has_channel(p->name)||channels.size()>=64)return false;
    channels.push_back({*p,{{sim.now,sim.bits(*p)}}});
    rebuild_listeners();
    return true;
  }
  bool Scope::remove_channel(size_t index)  {
    if(index>=channels.size())return false;
    channels.erase(channels.begin()+static_cast<std::ptrdiff_t>(index));
    if(trigger_channel==static_cast<int>(index))trigger_channel=-1;
    else if(trigger_channel>static_cast<int>(index))--trigger_channel;
    rebuild_listeners();
    return true;
  }
  bool Scope::move_channel(size_t index,int direction)  {
    if(direction!= -1&&direction!=1)return false;
    const auto target=static_cast<std::ptrdiff_t>(index)+direction;
    if(index>=channels.size()||target<0||target>=static_cast<std::ptrdiff_t>(channels.size()))return false;
    std::swap(channels[index],channels[static_cast<size_t>(target)]);
    if(trigger_channel==static_cast<int>(index))trigger_channel=static_cast<int>(target);
    else if(trigger_channel==static_cast<int>(target))trigger_channel=static_cast<int>(index);
    rebuild_listeners();
    return true;
  }
  Scope::~Scope()  {
    sim.observe=  {};
  }
  void Scope::arm()  {
    frozen=false;
    capture_end=-1;
    trigger_time=-1;
    next_trigger=sim.now;
  }
  void Scope::configure(const ScopeConfig& c)  {
    capacity=std::clamp<size_t>(c.capacity,2,1000000);
    span=std::max<Time>(1000,c.span);
    holdoff=std::max<Time>(0,c.holdoff);
    pretrigger=std::clamp(c.pretrigger,0.,.95);
    mode=c.mode=="single"?Single:c.mode=="normal"?Normal:Auto;
    rising=c.edge!="falling";
    both_edges=c.edge=="both";
    trigger_value=c.trigger_value;
    trigger_bit=c.bit;
    for(size_t i=0; i<channels.size(); i++)  {
      const auto& n=channels[i].probe.name;
      if(n==c.trigger||n.substr(0,n.rfind('.'))==c.trigger)trigger_channel=int(i);
    }
  }
  void Scope::poll(Time t)  {
    if(capture_end>=0&&t>capture_end&&mode==Single)frozen=true;
  }
  void Scope::record(Transition t)  {
    if(frozen)return;
    if(capture_end>=0&&t.time>capture_end&&mode==Single)  {
      frozen=true;
      return;
    }
    auto it=listeners.find(t.net);
    if(it==listeners.end())return;
    for(size_t c:it->second)  {
      auto& channel=channels[c];
      auto bits=sim.bits(channel.probe);
      auto before=channel.samples.empty()?bits:channel.samples.back().bits;
      if(bits==before)continue;
      if(static_cast<int>(c)==trigger_channel&&trigger_bit>=0&&static_cast<size_t>(trigger_bit)<bits.size())  {
        size_t b=bits.size()-1-static_cast<size_t>(trigger_bit);
        if(t.time>=next_trigger&&((before[b]=='0'&&bits[b]=='1'&&(rising||both_edges))||(before[b]=='1'&&bits[b]=='0'&&(!rising||both_edges)))&&(trigger_value.empty()||bits==trigger_value))  {
          trigger_time=t.time;
          capture_end=t.time+static_cast<Time>(span*(1-pretrigger));
          next_trigger=capture_end+holdoff;
        }
      }
      if(!channel.samples.empty()&&channel.samples.back().time==t.time)channel.samples.back().bits=bits;
      else channel.samples.push_back(  {
        t.time,bits
      }
      );
      while(channel.samples.size()>std::max(size_t(2),capacity))channel.samples.pop_front();
    }
  }
  std::string Scope::at(size_t c,Time t)const  {
    const auto& samples=channels.at(c).samples;
    if(samples.empty()||t<samples.front().time)return std::string(channels[c].probe.nets.size(),'x');
    auto it=std::upper_bound(samples.begin(),samples.end(),t,[](Time n,const Sample& s)  {
      return n<s.time;
    }
    );
    return std::prev(it)->bits;
  }
  Time Scope::available_begin()const  {
    Time begin=0;
    for(const auto& c:channels)if(!c.samples.empty())begin=std::max(begin,c.samples.front().time);
    return begin;
  }
  void Scope::export_vcd(const std::string& path,Time begin,Time end)const  {
    if(begin<available_begin()||end<begin||end>sim.now)throw std::runtime_error("export interval outside retained capture");
    std::ofstream f(path);
    if(!f)throw std::runtime_error("cannot write VCD");
    f<<"$version LcSim $end\n$timescale 1ps $end\n$scope module lcsim $end\n";
    for(size_t c=0; c<channels.size(); c++)  {
      std::string name=channels[c].probe.name;
      for(char& x:name)if(x==' '||x=='\n'||x=='\r')x='_';
      f<<"$var wire "<<channels[c].probe.nets.size()<<" s"<<c<<" "<<name<<" $end\n";
    }
    f<<"$upscope $end\n$enddefinitions $end\n#0\n$dumpvars\n";
    auto emit=[&](size_t c,const std::string& bits)  {
      if(bits.size()==1)f<<bits<<"s"<<c<<"\n";
      else f<<"b"<<bits<<" s"<<c<<"\n";
    };
    for(size_t c=0; c<channels.size(); c++)emit(c,at(c,begin));
    f<<"$end\n";
    std::map<Time,std::vector<std::pair<size_t,std::string>>> events;
    for(size_t c=0; c<channels.size(); c++)for(const auto& s:channels[c].samples)if(s.time>begin&&s.time<=end)events[s.time].push_back(  {
      c,s.bits
    }
    );
    for(const auto& [time,changes]:events)  {
      f<<"#"<<time-begin<<"\n";
      for(const auto& [c,bits]:changes)emit(c,bits);
    }
    f<<"#"<<end-begin<<"\n";
    if(!f)throw std::runtime_error("VCD write failed");
  }
  void Scope::export_csv(const std::string& path,Time begin,Time end)const  {
    if(begin<available_begin()||end<begin||end>sim.now)throw std::runtime_error("export interval outside retained capture");
    std::ofstream f(path);
    if(!f)throw std::runtime_error("cannot write CSV");
    f<<"time_ps";
    for(const auto& c:channels)  {
      f<<",\"";
      for(char x:c.probe.name)  {
        if(x=='\"')f<<'\"';
        f<<x;
      }
      f<<'\"';
    }
    f<<'\n';
    std::set<Time> times  {
      begin,end
    };
    for(const auto& c:channels)for(const auto& s:c.samples)if(s.time>begin&&s.time<end)times.insert(s.time);
    for(Time t:times)  {
      f<<t;
      for(size_t c=0; c<channels.size(); c++)f<<','<<at(c,t);
      f<<'\n';
    }
    if(!f)throw std::runtime_error("CSV write failed");
  }
}
