#include <lcsim/simulator.hpp>
#include <algorithm>
#include <cmath>
#include <iomanip>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
namespace lc  {
  namespace  {
    Logic inv(Logic x)  {
      return x==Logic::L?Logic::H:x==Logic::H?Logic::L:Logic::X;
    }
    Logic binary(Logic x)  {
      return x==Logic::Z?Logic::X:x;
    }
    bool pure(const std::string& t)  {
      return t=="AND"||t=="OR"||t=="XOR"||t=="NAND"||t=="NOR"||t=="NOT"||t=="BUF"||t=="TBUF"||t=="OC"||t=="MUX2"||t=="MUX4"||t=="DMUX2"||t=="DMUX4";
    }
    Time ps(double n)  {
      return static_cast<Time>(std::llround(n*1000));
    }
    int64_t address(const std::vector<Logic>& v,size_t offset,size_t width)  {
      uint64_t result=0;
      for(size_t b=0; b<width; b++)  {
        if(v[offset+b]!=Logic::L&&v[offset+b]!=Logic::H)return -1;
        if(v[offset+b]==Logic::H)result|=uint64_t(1)<<b;
      }
      return static_cast<int64_t>(result);
    }
  }
  Net Simulator::alloc()  {
    if(parent.size()>=10000000)throw std::runtime_error("flattened net limit exceeded");
    Net n=static_cast<Net>(parent.size());
    parent.push_back(n);
    nets.emplace_back();
    return n;
  }
  Net Simulator::root(Net n)  {
    return parent[n]==n?n:parent[n]=root(parent[n]);
  }
  void Simulator::join(Net a,Net b)  {
    if(a&&b)parent[root(b)]=root(a);
  }
  int Simulator::flatten(const Design& d,int def,const std::vector<Net>& ins,const std::vector<Net>& outs,const std::string& path,bool top)  {
    const auto& m=d.definitions.at(def);
    std::vector<Net> map(m.nets+1);
    for(size_t n=1; n<map.size(); n++)map[n]=alloc();
    for(size_t i=0; i<ins.size(); i++)join(ins[i],map.at(m.in.at(i)));
    for(size_t i=0; i<outs.size(); i++)join(outs[i],map.at(m.out.at(i)));
    int group=static_cast<int>(groups.size());
    groups.push_back(  {
      def,  {},  {},true
    }
    );
    std::unordered_map<std::string,Net> named;
    for(const auto& e:m.elements)if(e.type=="NODE"||e.type=="INOUT")  {
      Net wire=map.at(e.out[0]);
      join(wire,map.at(e.in[0]));
      if(!e.name.empty())  {
        auto [it,added]=named.emplace(e.name,wire);
        if(!added)join(wire,it->second);
      }
    }
    size_t ordinal=0;
    for(auto e:m.elements)  {
      for(auto& n:e.in)n=map.at(n);
      for(auto& n:e.out)n=n?map.at(n):alloc();
      // disconnected outputs are separate sinks
      if(e.type=="SWITCH")  {
        join(e.in[0],e.out[1]);
        join(e.in[2],e.out[0]);
      }
      std::string label=e.name.empty()?(e.module>=0?d.definitions[e.module].name:e.type)+"_"+std::to_string(ordinal):e.name;
      std::string full=path.empty()?label:path+"/"+label;
      ordinal++;
      if(e.module>=0)  {
        int child=flatten(d,e.module,e.in,e.out,full,false);
        groups[group].children.push_back(child);
        auto sub=groups[child].gates;
        groups[group].gates.insert(groups[group].gates.end(),sub.begin(),sub.end());
        groups[group].pure=groups[group].pure&&groups[child].pure;
        continue;
      }
      if(top&&(e.type=="INPUT"||e.type=="OUTPUT"||e.type=="NODE"||e.type=="INOUT"||e.type=="DISPLAY"))  {
        Probe p  {
          label,e.type=="OUTPUT"||e.type=="DISPLAY"?e.in:e.out,  {},e,e.type=="INPUT"
        };
        views.push_back(p);
      }
      if(e.type=="NODE"||e.type=="OUTPUT"||e.type=="INOUT"||e.type=="BUS"||e.type=="DISPLAY"||e.type=="OSCILLOSCOPE"||(e.type=="INPUT"&&!top))continue;
      Gate gate;
      gate.e=e;
      if(e.type=="SWITCH"){has_switches=true;gate.e.active_low=true;}
      gate.path=full;
      int id=static_cast<int>(gates.size());
      for(Net n:e.out)  {
        int di=static_cast<int>(drivers.size());
        drivers.push_back(  {
          n,Logic::Z,Logic::Z,e.type=="PULLUP"||e.type=="PULLDOWN",false,0
        }
        );
        gate.drivers.push_back(di);
      }
      if(top&&e.type=="INPUT")views.back().drivers=gate.drivers;
      if(e.type=="TERMINAL")gate.terminal=std::make_unique<Terminal>();
      if(e.type=="ROM"||e.type=="RAM")gate.e.memory.resize(size_t(1)<<e.aw);
      gates.push_back(std::move(gate));
      groups[group].gates.push_back(id);
      groups[group].pure=groups[group].pure&&pure(e.type);
    }
    return group;
  }
  Simulator::Simulator(const Design& d,Profile p,bool use_cache):profile(std::move(p))  {
    cache_enabled=use_cache;
    alloc();
    root_group=flatten(d,d.root,  {},  {},"",true);
    caches.resize(d.definitions.size());
    for(auto& g:gates)  {
      for(auto& n:g.e.in)n=root(n);
      for(auto& n:g.e.out)n=root(n);
    }
    for(size_t i=0; i<drivers.size(); i++)  {
      auto& dr=drivers[i];
      dr.net=root(dr.net);
      nets[dr.net].drivers.push_back(static_cast<int>(i));
    }
    for(size_t i=0; i<gates.size(); i++)for(Net n:gates[i].e.in)nets[n].users.push_back(static_cast<int>(i));
    for(auto& pview:views)for(auto& n:pview.nets)n=root(n);
    // Explicitly named decimal suffixes form little-endian logical buses.
    std::map<std::string,std::map<unsigned,const Probe*>> buses;
    for(const auto& v:views)  {
      if(v.visual.pixel||v.nets.size()!=1)continue;
      auto pos=v.name.rfind('.');
      if(pos==std::string::npos)continue;
      auto tail=v.name.substr(pos+1);
      size_t begin=tail.find_first_of("0123456789");
      if(begin==std::string::npos||tail.find_first_not_of("0123456789",begin)!=std::string::npos)continue;
      unsigned bit=static_cast<unsigned>(std::stoul(tail.substr(begin)));
      if(bit<64)buses[v.name.substr(0,pos)+"."+tail.substr(0,begin)][bit]=&v;
    }
    std::vector<Probe> combined;
    std::set<std::string> consumed;
    for(const auto& [name,parts]:buses)  {
      if(parts.size()<2||parts.rbegin()->first+1!=parts.size())continue;
      Probe v;
      v.name=name;
      v.visual=parts.begin()->second->visual;
      v.input=true;
      for(const auto& [bit,part]:parts)  {
        (void)bit;
        v.nets.push_back(part->nets[0]);
        v.input=v.input&&part->input;
        v.drivers.insert(v.drivers.end(),part->drivers.begin(),part->drivers.end());
        consumed.insert(part->name);
      }
      combined.push_back(v);
    }
    views.erase(std::remove_if(views.begin(),views.end(),[&](const Probe& v)  {
      return consumed.count(v.name)>0;
    }
    ),views.end());
    views.insert(views.end(),combined.begin(),combined.end());
    std::set<std::string> seen;
    views.erase(std::remove_if(views.begin(),views.end(),[&](const Probe& p)  {
      return !p.visual.pixel&&!seen.insert(p.name).second;
    }
    ),views.end());
    dirty.resize(gates.size(),true);
    for(size_t i=0; i<gates.size(); i++)  {
      auto& g=gates[i];
      auto t=g.e.type;
      if(t=="INPUT"||t=="CLK"||t=="H"||t=="L"||t=="PULLUP"||t=="PULLDOWN")  {
        Logic v=t=="INPUT"||t=="CLK"||t=="H"||t=="PULLUP"?Logic::H:Logic::L;
        for(int dr:g.drivers)schedule(dr,v,0,drivers[dr].weak);
      }
    }
    advance(0);
    while(!queue.empty())  {
      if(queue.top().at>100000000)throw std::runtime_error("startup did not settle within 100 us");
      advance(queue.top().at-now);
    }
    now=0;
    initializing=false;
    for(size_t i=0; i<gates.size(); i++)  {
      auto& g=gates[i];
      g.data_changed=-1000000000;
      g.edge=-1000000000;
      if(g.e.type=="CLK")enqueue(profile.tick*g.e.period,1,static_cast<int>(i));
    }
  }
  void Simulator::enqueue(Time at,int kind,int id,Logic v,uint64_t gen,bool weak)  {
    queue.push(  {
      at,sequence++,kind,id,v,gen,weak
    }
    );
  }
  Time Simulator::delay(const Gate& g)const  {
    if(g.e.cycles>=0)return static_cast<Time>(std::llround(g.e.cycles*profile.tick));
    if(g.e.ns>=0)return ps(g.e.ns);
    return g.e.type=="D_FF"?profile.cq:g.e.type=="SWITCH"?profile.sw:profile.gate;
  }
  void Simulator::schedule(int id,Logic v,Time dt,bool weak)  {
    auto& d=drivers.at(id);
    if(d.pending&&d.target==v&&d.target_weak==weak)return;
    if(!d.pending&&d.value==v&&d.weak==weak)return;
    d.generation++;
    d.pending=false;
    d.target=v;
    d.target_weak=weak;
    if(d.value==v&&d.weak==weak)return;
    d.pending=true;
    enqueue(now+dt,0,id,v,d.generation,weak);
  }
  void Simulator::resolve()  {
    if(!has_switches)  {
      std::sort(touched.begin(),touched.end());
      touched.erase(std::unique(touched.begin(),touched.end()),touched.end());
      for(Net n:touched)  {
        Logic strong=Logic::Z,weak=Logic::Z;
        for(int id:nets[n].drivers)  {
          const auto& d=drivers[id];
          if(d.value==Logic::Z)continue;
          Logic& v=d.weak?weak:strong;
          v=v==Logic::Z?d.value:v==d.value?v:Logic::X;
        }
        Logic v=strong==Logic::Z?weak:strong;
        bool is_weak=strong==Logic::Z;
        if(v==nets[n].value&&is_weak==nets[n].weak)continue;
        nets[n].value=v;
        nets[n].weak=is_weak;
        for(int g:nets[n].users)dirty[g]=true;
        if(observe)observe(  {
          now,n,v
        }
        );
      }
      touched.clear();
      return;
    }
    touched.clear();
    // Enabled switches join terminals without driving them, so no self-sustaining echo.
    std::vector<Net> links(nets.size());
    std::iota(links.begin(),links.end(),0);
    auto find=[&](Net n)  {
      while(links[n]!=n)  {
        links[n]=links[links[n]];
        n=links[n];
      }
      return n;
    };
    for(const auto& g:gates)if(g.e.type=="SWITCH"&&g.switch_state==Logic::H)  {
      Net a=g.e.out[1],b=g.e.out[0];
      links[find(b)]=find(a);
      if(g.e.in[0])links[find(g.e.in[0])]=find(a);
      if(g.e.in[2])links[find(g.e.in[2])]=find(b);
    }
    struct Acc  {
      Logic strong=Logic::Z,weak=Logic::Z;
    };
    std::vector<Acc> acc(nets.size());
    auto merge=[](Logic& a,Logic b)  {
      if(b==Logic::Z)return;
      if(a==Logic::Z)a=b;
      else if(a!=b)a=Logic::X;
    };
    for(const auto& d:drivers)  {
      auto& a=acc[find(d.net)];
      merge(d.weak?a.weak:a.strong,d.value);
    }
    for(const auto& g:gates)if(g.e.type=="SWITCH"&&g.switch_state==Logic::X)  {
      Net a=find(g.e.out[1]),b=find(g.e.out[0]);
      auto level=[&](Net n)  {
        return acc[n].strong==Logic::Z?acc[n].weak:acc[n].strong;
      };
      if(level(a)!=level(b))  {
        acc[a].strong=Logic::X;
        acc[b].strong=Logic::X;
      }
    }
    for(Net n=0; n<nets.size(); n++)  {
      const auto& a=acc[find(n)];
      Logic v=n==0?Logic::Z:a.strong==Logic::Z?a.weak:a.strong;
      bool is_weak=a.strong==Logic::Z;
      if(v!=nets[n].value||is_weak!=nets[n].weak)  {
        nets[n].value=v;
        nets[n].weak=is_weak;
        for(int g:nets[n].users)dirty[g]=true;
        if(observe)observe(  {
          now,n,v
        }
        );
      }
    }
  }
  std::vector<Logic> Simulator::inputs(const Gate& g)const  {
    std::vector<Logic> v;
    v.reserve(g.e.in.size());
    for(Net n:g.e.in)v.push_back(value(n));
    return v;
  }
  std::vector<Logic> Simulator::evaluate_pure(const Gate& g)  {
    stats.evaluations++;
    auto v=inputs(g);
    const auto& t=g.e.type;
    if(t=="TBUF")  {
      Logic en=binary(v[1]);
      if(g.e.active_low)en=inv(en);
      return  {
        en==Logic::H?v[0]:Logic::Z
      };
    }
    if(t=="OC")return  {
      v[0]==Logic::H?Logic::L:Logic::Z
    };
    for(auto& x:v)x=binary(x);
    if(t=="NOT")return  {
      inv(v[0])
    };
    if(t=="BUF")return  {
      v[0]
    };
    if(t.find("MUX")!=std::string::npos)  {
      bool dem=t[0]=='D';
      unsigned count=t.back()=='4'?4:2,offset=dem?1:count;
      std::vector<Logic> out(dem?count:1,Logic::X);
      bool first=true;
      for(unsigned c=0; c<count; c++)  {
        if(v[offset]!=Logic::X&&static_cast<unsigned>(v[offset])!=(c&1))continue;
        if(count==4&&v[offset+1]!=Logic::X&&static_cast<unsigned>(v[offset+1])!=(c>>1))continue;
        for(size_t p=0; p<out.size(); p++)  {
          Logic x=dem?(p==c?v[0]:Logic::L):v[c];
          out[p]=first||out[p]==x?x:Logic::X;
        }
        first=false;
      }
      return out;
    }
    bool andgate=t=="AND"||t=="NAND",orgate=t=="OR"||t=="NOR";
    Logic r=andgate?Logic::H:Logic::L;
    for(Logic x:v)  {
      if(andgate)  {
        if(x==Logic::L)  {
          r=Logic::L;
          break;
        }
        if(x==Logic::X)r=Logic::X;
      }
      else if(orgate)  {
        if(x==Logic::H)  {
          r=Logic::H;
          break;
        }
        if(x==Logic::X)r=Logic::X;
      }
      else  {
        if(x==Logic::X||r==Logic::X)r=Logic::X;
        else if(x==Logic::H)r=inv(r);
      }
    }
    if(t=="NAND"||t=="NOR")r=inv(r);
    return  {
      r
    };
  }
  void Simulator::apply(int id,const std::vector<Logic>& values)  {
    const auto& g=gates[id];
    for(size_t p=0; p<values.size(); p++)schedule(g.drivers.at(p),values[p],delay(g),g.e.type=="TBUF"&&nets[g.e.in[0]].weak);
  }
  void Simulator::evaluate_stateful(int id)  {
    auto& g=gates[id];
    const auto& t=g.e.type;
    auto v=inputs(g);
    if(t=="SWITCH")  {
      Logic en=binary(v[1]);
      if(g.e.active_low)en=inv(en);
      if(g.last_data!=en)  {
        g.last_data=en;
        enqueue(now+delay(g),3,id,en,++g.read_generation);
      }
      return;
    }
    if(t=="D_LATCH")  {
      Logic en=binary(v[1]),data=binary(v[0]);
      if(v[0]!=Logic::Z)  {
        if(en==Logic::H)g.stored=data;
        else if(en==Logic::X&&data!=g.stored)g.stored=Logic::X;
      }
      apply(id,  {
        g.stored,inv(g.stored)
      }
      );
      return;
    }
    if(t=="D_FF")  {
      Logic clk=binary(v[0]),data=binary(v[1]);
      Time setup=g.e.setup>=0?ps(g.e.setup):profile.setup,hold=g.e.hold>=0?ps(g.e.hold):profile.hold;
      if(data!=g.last_data)  {
        g.data_changed=now;
        if(g.edge>=0&&now-g.edge<hold)g.stored=Logic::X;
        g.last_data=data;
      }
      if(!initializing&&clk==Logic::H&&g.last_clock!=Logic::H)  {
        g.edge=now;
        g.stored=now-g.data_changed<setup?Logic::X:data;
      }
      g.last_clock=clk;
      apply(id,  {
        g.stored,inv(g.stored)
      }
      );
      return;
    }
    if(t=="TERMINAL") {
      const auto a=address(v,0,16);
      const int reg=a>=int64_t(g.e.io_base)&&a<int64_t(g.e.io_base)+4?int(a-g.e.io_base):-1;
      const bool read=reg>=0&&v[24]==Logic::L&&v[25]==Logic::H;
      const bool write=reg>=0&&v[25]==Logic::L&&v[24]==Logic::H;
      if(g.terminal_read&&(!read||reg!=g.terminal_reg)) {
        if(g.terminal_reg==0&&g.terminal_read_value&0x80)g.terminal->consume();
        g.terminal_read=false;
      }
      if(read&&!g.terminal_read) {
        g.terminal_read=true;g.terminal_reg=reg;
        g.terminal_read_value=g.terminal->read(unsigned(reg));
      }
      // Commit once on a clean /WR rising edge. Address/data may settle while low.
      if(g.terminal_write&&!write) {
        if(v[25]==Logic::H&&reg==g.terminal_write_reg&&g.terminal_write_valid)
          g.terminal->write(unsigned(g.terminal_write_reg),g.terminal_write_value);
        g.terminal_write=false;
      }
      if(write) {
        const auto data=address(v,16,8);
        g.terminal_write=true;g.terminal_write_reg=reg;
        g.terminal_write_valid=data>=0;g.terminal_write_value=uint8_t(data<0?0:data);
      }
      for(size_t b=0;b<g.drivers.size();b++)schedule(g.drivers[b],
        read?((g.terminal_read_value>>b)&1?Logic::H:Logic::L):Logic::Z,0);
      return;
    }
    if(t=="RAM"||t=="ROM")  {
      int64_t addr=address(v,0,g.e.aw);
      bool changed=false;
      if(t=="RAM"&&v[g.e.aw+g.e.dw]==Logic::L)  {
        bool valid=addr>=0;
        uint64_t word=0;
        for(size_t b=0; b<g.e.dw; b++)  {
          Logic x=v[g.e.aw+b];
          if(x!=Logic::L&&x!=Logic::H)valid=false;
          if(x==Logic::H)word|=uint64_t(1)<<b;
        }
        if(valid)  {
          auto& cell=g.e.memory[static_cast<size_t>(addr)];
          changed=cell!=word;
          cell=word;
        }
        else stats.invalid_writes++;
      }
      if(addr!=g.address)  {
        g.address=addr;
        enqueue(now+ps(g.e.memory_ns),2,id,Logic::X,++g.read_generation);
      }
      else if(changed&&g.settled_address==addr&&addr>=0)g.read_word=g.e.memory[static_cast<size_t>(addr)];
      size_t oe=t=="ROM"?g.e.aw:g.e.aw+g.e.dw+1;
      for(size_t b=0; b<g.drivers.size(); b++)  {
        Logic out=Logic::Z;
        if(v[oe]==Logic::L)out=!g.ready?Logic::Z:g.settled_address<0?Logic::X:(g.read_word>>b)&1?Logic::H:Logic::L;
        else if(v[oe]!=Logic::H)out=Logic::X;
        schedule(g.drivers[b],out,0);
      }
    }
  }
  void Simulator::evaluate_group(int id,const std::vector<bool>& work)  {
    auto& group=groups[id];
    if(cache_enabled&&group.pure&&group.gates.size()>=2)  {
      // Exact per-event-batch signature includes INTERNAL inputs and the dirty mask.
      // Cache replays evaluations, never time or pending state; inertial scheduling stays authoritative.
      std::string key;
      std::vector<int> active;
      for(size_t k=0; k<group.gates.size(); k++)  {
        int g=group.gates[k];
        if(!work[g])continue;
        active.push_back(static_cast<int>(k));
        uint32_t n=static_cast<uint32_t>(k);
        for(int b=0; b<4; b++)key.push_back(static_cast<char>((n>>(8*b))&255));
        for(Net n:gates[g].e.in)  {
          key.push_back(digit(value(n)));
          key.push_back(nets[n].weak?'w':'s');
        }
      }
      if(active.empty())return;
      auto& cache=caches[group.definition].entries;
      auto it=cache.find(key);
      if(it!=cache.end())  {
        stats.hits++;
        for(const auto& r:it->second)apply(group.gates[r.index],r.values);
        return;
      }
      stats.misses++;
      // Recurse first: a larger module can learn from already cached child modules.
      std::vector<bool> direct=work;
      for(int child:group.children)  {
        evaluate_group(child,work);
        for(int g:groups[child].gates)direct[g]=false;
      }
      for(int g:group.gates)if(direct[g])apply(g,evaluate_pure(gates[g]));
      std::vector<Result> plan;
      size_t bytes=key.size()+128;
      for(int k:active)  {
        Result r  {
          k,  {}
        };
        for(int d:gates[group.gates[k]].drivers)r.values.push_back(drivers[d].target);
        bytes+=sizeof(Result)+r.values.size();
        plan.push_back(std::move(r));
      }
      if(stats.cache_bytes+bytes<=cache_budget)  {
        cache.emplace(std::move(key),std::move(plan));
        stats.cache_bytes+=bytes;
      }
      return;
    }
    std::vector<bool> direct=work;
    for(int child:group.children)  {
      evaluate_group(child,work);
      for(int g:groups[child].gates)direct[g]=false;
    }
    for(int g:group.gates)if(direct[g])  {
      if(pure(gates[g].e.type))apply(g,evaluate_pure(gates[g]));
      else evaluate_stateful(g);
    }
  }
  void Simulator::evaluate_dirty()  {
    auto work=dirty;
    std::fill(dirty.begin(),dirty.end(),false);
    evaluate_group(root_group,work);
  }
  void Simulator::advance(Time duration)  {
    if(duration<0)throw std::runtime_error("negative duration");
    Time end=now+duration;
    uint64_t same_time_events=0;
    Time previous=-1;
    evaluate_dirty();
    while(!queue.empty()&&queue.top().at<=end)  {
      Time t=queue.top().at;
      now=t;
      if(t!=previous)  {
        same_time_events=0;
        previous=t;
      }
      bool changed=false;
      do  {
        Event e=queue.top();
        queue.pop();
        if(++same_time_events>1000000)throw std::runtime_error("zero-delay oscillation at "+std::to_string(now)+" ps");
        stats.events++;
        if(e.kind==0)  {
          auto& d=drivers[e.id];
          if(d.generation!=e.generation)continue;
          d.pending=false;
          d.value=e.value;
          d.weak=e.weak;
          touched.push_back(d.net);
          changed=true;
        }
        else if(e.kind==1)  {
          auto& g=gates[e.id];
          if(auto_clock)schedule(g.drivers[0],inv(drivers[g.drivers[0]].value),0);
          enqueue(now+profile.tick*g.e.period,1,e.id);
        }
        else if(e.kind==2)  {
          auto& g=gates[e.id];
          if(e.generation!=g.read_generation)continue;
          g.ready=true;
          g.settled_address=g.address;
          if(g.address>=0)g.read_word=g.e.memory[static_cast<size_t>(g.address)];
          dirty[e.id]=true;
        }
        else if(e.kind==3)  {
          auto& g=gates[e.id];
          if(e.generation!=g.read_generation)continue;
          g.switch_state=e.value;
          changed=true;
        }
      }
      while(!queue.empty()&&queue.top().at==t);
      if(changed)resolve();
      evaluate_dirty();
    }
    now=end;
  }
  const Probe* Simulator::find(const std::string& name)const  {
    for(const auto& p:views)if(p.name==name)return &p;
    return nullptr;
  }
  void Simulator::drive(const std::string& name,const std::string& text)  {
    auto p=find(name);
    if(!p||!p->input)throw std::runtime_error("not an editable INPUT: "+name);
    std::string bits=text;
    if(text.size()>2&&text.substr(0,2)=="0x")  {
      size_t used=0;
      uint64_t n=std::stoull(text,&used,16);
      if(used!=text.size()||(p->drivers.size()<64&&(n>>p->drivers.size())!=0))throw std::runtime_error("INPUT hex value exceeds width or contains invalid characters");
      bits="";
      for(size_t b=0; b<p->drivers.size(); b++)bits.insert(bits.begin(),(n>>b)&1?'1':'0');
    }
    if(bits.size()==1)bits=std::string(p->drivers.size(),bits[0]);
    if(bits.size()!=p->drivers.size()||bits.find_first_not_of("01xXzZ")!=std::string::npos)throw std::runtime_error("INPUT value must be binary, 0x hex, X or Z");
    for(size_t b=0; b<p->drivers.size(); b++)schedule(p->drivers[b],logic(bits[bits.size()-1-b]),0);
    advance(0);
  }
  std::string Simulator::bits(const Probe& p)const  {
    std::string s;
    for(Net n:p.nets)s.insert(s.begin(),digit(value(n)));
    return s;
  }
  std::string Simulator::hex(const Probe& p)const  {
    auto s=bits(p);
    if(s.find('x')!=std::string::npos)return "X";
    if(s.find('z')!=std::string::npos)return s.find_first_not_of('z')==std::string::npos?"Z":"X/Z";
    if(s.size()==1)return s;
    std::string result;
    for(size_t end=s.size();
    end;
    )  {
      size_t start=end>=4?end-4:0;
      int n=std::stoi(s.substr(start,end-start),nullptr,2);
      result.insert(result.begin(),"0123456789ABCDEF"[n]);
      end=start;
    }
    return "0x"+result;
  }
  std::vector<std::pair<std::string,std::vector<uint64_t>>> Simulator::memories()const  {
    std::vector<std::pair<std::string,std::vector<uint64_t>>> r;
    for(const auto& g:gates)if(g.e.type=="RAM")r.emplace_back(g.path,g.e.memory);
    return r;
  }
  std::vector<MemoryInfo> Simulator::memory_info()const  {
    std::vector<MemoryInfo> result;
    for(const auto& g:gates)if(g.e.type=="RAM"||g.e.type=="ROM")result.push_back({g.path,g.e.type,g.e.aw,g.e.dw,g.e.memory.size()});
    return result;
  }
  std::vector<uint64_t> Simulator::memory_data(const std::string& name)const  {
    for(const auto& g:gates)if((g.e.type=="RAM"||g.e.type=="ROM")&&g.path==name)return g.e.memory;
    throw std::runtime_error("unknown memory: "+name);
  }
  uint64_t Simulator::memory_word(const std::string& name,size_t address)const  {
    for(const auto& g:gates)if((g.e.type=="RAM"||g.e.type=="ROM")&&g.path==name)  {
      if(address>=g.e.memory.size())throw std::runtime_error("memory address outside device depth");
      return g.e.memory[address];
    }
    throw std::runtime_error("unknown memory: "+name);
  }
  void Simulator::replace_memory(const std::string& name,const std::vector<uint64_t>& values)  {
    for(size_t id=0;id<gates.size();id++)  {
      auto& g=gates[id];
      if((g.e.type!="RAM"&&g.e.type!="ROM")||g.path!=name)continue;
      if(values.size()>g.e.memory.size())throw std::runtime_error("memory image exceeds "+std::to_string(g.e.memory.size())+" words");
      uint64_t limit=g.e.dw==64?~uint64_t(0):(uint64_t(1)<<g.e.dw)-1;
      if(std::any_of(values.begin(),values.end(),[&](uint64_t value){return value>limit;}))throw std::runtime_error("memory word exceeds "+std::to_string(g.e.dw)+" bits");
      std::fill(g.e.memory.begin(),g.e.memory.end(),0);
      std::copy(values.begin(),values.end(),g.e.memory.begin());
      if(g.ready&&g.settled_address>=0)g.read_word=g.e.memory[static_cast<size_t>(g.settled_address)];
      dirty[id]=true;
      advance(0);
      return;
    }
    throw std::runtime_error("unknown memory: "+name);
  }
  std::vector<std::pair<std::string,Terminal*>> Simulator::terminals() {
    std::vector<std::pair<std::string,Terminal*>> result;
    for(auto& gate:gates)if(gate.terminal)result.emplace_back(gate.path,gate.terminal.get());
    return result;
  }
  bool Simulator::terminal_send(const std::string& name,const std::string& text) {
    for(size_t i=0;i<gates.size();i++)if(gates[i].terminal&&gates[i].path==name) {
      bool accepted=gates[i].terminal->send(text);dirty[i]=true;advance(0);return accepted;
    }
    throw std::runtime_error("unknown terminal: "+name);
  }
  std::string Simulator::diagnostics()const  {
    std::ostringstream out;
    for(const auto& g:gates)  {
      out<<g.path<<" "<<g.e.type<<" in=";
      for(Net n:g.e.in)out<<digit(value(n));
      out<<" out=";
      for(int d:g.drivers)out<<digit(drivers[d].value);
      out<<"\n";
    }
    return out.str();
  }
}
