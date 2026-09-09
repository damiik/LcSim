#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>
namespace lc  {
  using Time = int64_t;
  // integer picoseconds
  using Net = uint32_t;
  enum class Logic : uint8_t  {
    L, H, X, Z
  };
  inline char digit(Logic v)  {
    return "01xz"[static_cast<unsigned>(v)];
  }
  inline Logic logic(char c)  {
    return c=='0'?Logic::L:c=='1'?Logic::H:c=='z'||c=='Z'?Logic::Z:Logic::X;
  }
  struct Element  {
    std::string type, name;
    std::vector<Net> in, out;
    int module=-1;
    double cycles=-1, ns=-1, setup=-1, hold=-1;
    uint32_t period=10, aw=4, dw=8, io_base=0xd010;
    double memory_ns=0;
    bool active_low=false;
    std::vector<uint64_t> memory;
    double x=0,y=0,size=16;
    std::string shape="circle", on="#a8ffaa", off="#3b351d", mode="hex";
    bool pixel=false;
  };
  struct Definition  {
    std::string name;
    uint32_t nets=0;
    std::vector<Net> in,out;
    std::vector<Element> elements;
  };
  struct ScopeConfig  {
    size_t capacity=4096;
    Time span=1000000,holdoff=0;
    double pretrigger=.3;
    std::string mode="auto",trigger,edge="rising",trigger_value;
    int bit=0;
  };
  struct Design  {
    std::string name;
    std::vector<Definition> definitions;
    int root=0;
    std::vector<std::string> scope;
    ScopeConfig scope_config;
  };
  Design make_design();
  struct Profile  {
    std::string name;
    Time tick, gate, cq, setup, hold, sw;
    static Profile fpga()  {
      return  {
        "FPGA",1250,500,500,300,100,500
      };
    }
    static Profile lvc()  {
      return  {
        "LVC",2500,2000,2500,1000,200,4000
      };
    }
  };
}
