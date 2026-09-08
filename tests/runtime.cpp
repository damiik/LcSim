#include <lcsim/scope.hpp>
#include <iostream>
#include <stdexcept>
#include <fstream>
using namespace lc;
void check(bool b,const char* what)  {
  if(!b)throw std::runtime_error(what);
}
Element e(std::string t,std::vector<Net> in,std::vector<Net> out,std::string name="")  {
  Element x;
  x.type=t;
  x.in=in;
  x.out=out;
  x.name=name;
  return x;
}
Design circuit(std::vector<Element> gates)  {
  Design d;
  Definition m;
  m.name="test";
  m.nets=30;
  m.elements=gates;
  d.definitions.push_back(m);
  return d;
}
Logic val(Simulator& s,std::string p)  {
  return s.value(s.find(p)->nets[0]);
}
int main()  {
  for(auto profile:  {
    Profile::lvc(),Profile::fpga()
  }
  )  {
    auto gate=e("AND",  {
      1,2
    },  {
      3
    }
    );
    gate.cycles=4;
    auto d=circuit(  {
      e("INPUT",  {},  {
        1
      },"A"),e("INPUT",  {},  {
        2
      },"B"),gate,e("OUTPUT",  {
        3
      },  {},"Q")
    }
    );
    Simulator s(d,profile);
    s.drive("A","0");
    s.drive("B","0");
    s.advance(100000);
    s.drive("A","1");
    s.drive("B","1");
    s.advance(4*profile.tick-1);
    check(val(s,"Q")==Logic::L,"scaled delay too early");
    s.advance(1);
    check(val(s,"Q")==Logic::H,"scaled delay late");
    s.drive("A","0");
    s.advance(profile.tick);
    s.drive("A","1");
    s.advance(5*profile.tick);
    check(val(s,"Q")==Logic::H,"inertial cancellation");
    auto ff=circuit(  {
      e("INPUT",  {},  {
        1
      },"CLK"),e("INPUT",  {},  {
        2
      },"D"),e("D_FF",  {
        1,2
      },  {
        3,4
      }
      ),e("OUTPUT",  {
        3
      },  {},"Q")
    }
    );
    Simulator f(ff,profile);
    f.drive("CLK","0");
    f.drive("D","0");
    f.advance(100000);
    f.drive("D","1");
    f.advance(10000);
    f.drive("CLK","1");
    f.advance(profile.cq);
    check(val(f,"Q")==Logic::H,"DFF edge");
    f.drive("CLK","0");
    f.advance(10000);
    f.drive("D","0");
    f.drive("CLK","1");
    f.advance(profile.cq);
    check(val(f,"Q")==Logic::X,"DFF setup violation");
  }
  auto sw=circuit(  {
    e("INPUT",  {},  {
      1
    },"A"),e("INPUT",  {},  {
      2
    },"EN_N"),e("INPUT",  {},  {
      3
    },"B"),e("SWITCH",  {
      1,2,3
    },  {
      4,5
    }
    ),e("OUTPUT",  {
      5
    },  {},"Aout"),e("OUTPUT",  {
      4
    },  {},"Bout")
  }
  );
  Simulator s(sw);
  s.drive("EN_N","0");
  s.drive("A","Z");
  s.drive("B","1");
  s.advance(10000);
  check(val(s,"Aout")==Logic::H,"reverse switch");
  s.drive("A","0");
  check(val(s,"Aout")==Logic::X,"switch contention");
  s.drive("EN_N","1");
  s.advance(10000);
  check(val(s,"Aout")==Logic::L&&val(s,"Bout")==Logic::H,"switch off separates terminals");
  auto latch=circuit(  {
    e("INPUT",  {},  {
      1
    },"D"),e("INPUT",  {},  {
      2
    },"LE"),e("D_LATCH",  {
      1,2
    },  {
      3,4
    }
    ),e("OUTPUT",  {
      3
    },  {},"Q")
  }
  );
  Simulator l(latch);
  l.drive("D","1");
  l.drive("LE","1");
  l.advance(10000);
  l.drive("D","Z");
  l.advance(10000);
  check(val(l,"Q")==Logic::H,"Logic Cosmos Hi-Z latch compatibility");
  l.drive("D","X");
  l.advance(10000);
  check(val(l,"Q")==Logic::X,"driven X is not retained");
  Design hierarchy;
  Definition m;
  m.name="pair";
  m.nets=4;
  m.in=  {
    1,2
  };
  m.out=  {
    4
  };
  m.elements=  {
    e("XOR",  {
      1,2
    },  {
      3
    }
    ),e("NOT",  {
      3
    },  {
      4
    }
    )
  };
  hierarchy.definitions.push_back(m);
  Definition root;
  root.nets=5;
  root.elements=  {
    e("INPUT",  {},  {
      1
    },"A"),e("INPUT",  {},  {
      2
    },"B"),e("MODULE",  {
      1,2
    },  {
      3
    }
    ),e("MODULE",  {
      3,2
    },  {
      4
    }
    ),e("OUTPUT",  {
      4
    },  {},"Q")
  };
  root.elements[2].module=0;
  root.elements[3].module=0;
  hierarchy.root=1;
  hierarchy.definitions.push_back(root);
  Simulator cached(hierarchy),plain(hierarchy);
  plain.cache_enabled=false;
  Scope cap(cached,  {
    "Q"
  }
  );
  std::string trace1,trace2;
  cached.observe=[&](Transition t)  {
    trace1+=std::to_string(t.time)+":"+std::to_string(t.net)+digit(t.value)+";";
    cap.record(t);
  };
  plain.observe=[&](Transition t)  {
    trace2+=std::to_string(t.time)+":"+std::to_string(t.net)+digit(t.value)+";";
  };
  for(int i=0; i<200; i++)  {
    for(auto* sim:  {
      &cached,&plain
    }
    )  {
      sim->drive("A",i%2?"1":"0");
      sim->drive("B",i%3?"1":"Z");
      sim->advance(i%4?20000:500);
    }
  }
  check(trace1==trace2,"cache changed timestamped trace");
  check(cached.stats.hits>20,"hierarchical cache unused");
  cap.export_vcd("build/test.vcd",cap.available_begin(),cached.now);
  cap.export_csv("build/test.csv",cap.available_begin(),cached.now);
  std::cout<<"PASS: scaled timing, inertial cancellation, DFF, latch, bidirectional SW, hierarchical cache trace equivalence, VCD/CSV\n";
}
