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

  // Gate/element kind. Replaces the previous std::string type field, which
  // forced every hot-path comparison in the simulator to go through
  // std::string operator== / find(). Using a scoped enum turns those checks
  // into a single byte compare (or a jump table after the compiler is done).
  //
  // The set of enumerators must stay in sync with:
  //   - PRIMITIVES / FIXED in scripts/lc_compile.py
  //   - the mapping table in scripts/lc_compile.py that emits GateType::X
  //   - to_string() below
  enum class GateType : uint8_t  {
    UNKNOWN = 0,
    // pure combinational
    // pure combinational
    AND, OR, XOR, NAND, NOR, NOT, BUF, TBUF, OC,
    // 2-input specializations emitted by lc_compile.py for the hot path
    AND2, OR2, XOR2, NAND2, NOR2,
    MUX2, MUX4, DMUX2, DMUX4,
    // stateful primitives
    D_FF, D_LATCH, SWITCH,
    // sources / constants
    H, L, PULLUP, PULLDOWN, CLK, INPUT,
    // wiring / views / pass-through
    NODE, INOUT, OUTPUT, BUS, DISPLAY, OSCILLOSCOPE,
    // memory / IO
    ROM, RAM, TERMINAL,
    // hierarchy
    MODULE
  };

  inline const char* to_string(GateType t)  {
    switch(t)  {
      case GateType::AND:          return "AND";
      case GateType::OR:           return "OR";
      case GateType::XOR:          return "XOR";
      case GateType::NAND:         return "NAND";
      case GateType::NOR:          return "NOR";
      case GateType::AND2:         return "AND";
      case GateType::OR2:          return "OR";
      case GateType::XOR2:         return "XOR";
      case GateType::NAND2:        return "NAND";
      case GateType::NOR2:         return "NOR";
      case GateType::NOT:          return "NOT";
      case GateType::BUF:          return "BUF";
      case GateType::TBUF:         return "TBUF";
      case GateType::OC:           return "OC";
      case GateType::MUX2:         return "MUX2";
      case GateType::MUX4:         return "MUX4";
      case GateType::DMUX2:        return "DMUX2";
      case GateType::DMUX4:        return "DMUX4";
      case GateType::D_FF:         return "D_FF";
      case GateType::D_LATCH:      return "D_LATCH";
      case GateType::SWITCH:       return "SWITCH";
      case GateType::H:            return "H";
      case GateType::L:            return "L";
      case GateType::PULLUP:       return "PULLUP";
      case GateType::PULLDOWN:     return "PULLDOWN";
      case GateType::CLK:          return "CLK";
      case GateType::INPUT:        return "INPUT";
      case GateType::NODE:         return "NODE";
      case GateType::INOUT:        return "INOUT";
      case GateType::OUTPUT:       return "OUTPUT";
      case GateType::BUS:          return "BUS";
      case GateType::DISPLAY:      return "DISPLAY";
      case GateType::OSCILLOSCOPE: return "OSCILLOSCOPE";
      case GateType::ROM:          return "ROM";
      case GateType::RAM:          return "RAM";
      case GateType::TERMINAL:     return "TERMINAL";
      case GateType::MODULE:       return "MODULE";
      default:                     return "UNKNOWN";
    }
  }

  // Parser helper: TOML string -> enum. Returns GateType::UNKNOWN for
  // unrecognised names, matching the old "unknown string" behaviour where
  // such an Element simply never matched any branch.
  inline GateType gate_type(const std::string& s)  {
    if(s=="AND")return GateType::AND;
    if(s=="OR")return GateType::OR;
    if(s=="XOR")return GateType::XOR;
    if(s=="NAND")return GateType::NAND;
    if(s=="NOR")return GateType::NOR;
    if(s=="AND2")return GateType::AND2;
    if(s=="OR2")return GateType::OR2;
    if(s=="XOR2")return GateType::XOR2;
    if(s=="NAND2")return GateType::NAND2;
    if(s=="NOR2")return GateType::NOR2;
    if(s=="NOT")return GateType::NOT;
    if(s=="BUF")return GateType::BUF;
    if(s=="TBUF")return GateType::TBUF;
    if(s=="OC")return GateType::OC;
    if(s=="MUX2")return GateType::MUX2;
    if(s=="MUX4")return GateType::MUX4;
    if(s=="DMUX2")return GateType::DMUX2;
    if(s=="DMUX4")return GateType::DMUX4;
    if(s=="D_FF"||s=="DFF")return GateType::D_FF;
    if(s=="D_LATCH")return GateType::D_LATCH;
    if(s=="SWITCH"||s=="SW")return GateType::SWITCH;
    if(s=="H")return GateType::H;
    if(s=="L")return GateType::L;
    if(s=="PULLUP"||s=="PULL")return GateType::PULLUP;
    if(s=="PULLDOWN")return GateType::PULLDOWN;
    if(s=="CLK")return GateType::CLK;
    if(s=="INPUT")return GateType::INPUT;
    if(s=="NODE")return GateType::NODE;
    if(s=="INOUT")return GateType::INOUT;
    if(s=="OUTPUT")return GateType::OUTPUT;
    if(s=="BUS")return GateType::BUS;
    if(s=="DISPLAY")return GateType::DISPLAY;
    if(s=="OSCILLOSCOPE")return GateType::OSCILLOSCOPE;
    if(s=="ROM")return GateType::ROM;
    if(s=="RAM")return GateType::RAM;
    if(s=="TERMINAL")return GateType::TERMINAL;
    if(s=="MODULE")return GateType::MODULE;
    return GateType::UNKNOWN;
  }

  struct Element  {
    GateType type=GateType::UNKNOWN;
    std::string name;
    std::vector<Net> in, out;
    int module=-1;
    double cycles=-1, ns=-1, setup=-1, hold=-1;
    std::string io_mode="apple1";
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