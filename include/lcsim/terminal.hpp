#pragma once
#include <cstdint>
#include <deque>
#include <string>
#include <vector>
namespace lc {
// A polling Apple-1-style terminal interface, not a complete 6820 PIA.
class Terminal {
public:
  static constexpr size_t input_limit=4096, history_limit=512, transcript_limit=65536;
  std::deque<uint8_t> keys;
  std::deque<std::string> lines{std::string{}};
  std::string transcript;
  uint8_t keyboard_control=0,display_control=0;
  size_t dropped=0;
  bool send(const std::string& text) {
    std::vector<uint8_t> encoded;
    bool cr=false;
    for(unsigned char c:text) {
      if(c=='\n'&&cr){cr=false;continue;}
      cr=c=='\r';if(c=='\n')c='\r';
      if(c>='a'&&c<='z')c-=32;
      if(c==8||c==127)c='_';
      if(c=='\r'||c==27||(c>=32&&c<127))encoded.push_back(c|0x80);
    }
    if(keys.size()+encoded.size()>input_limit){dropped+=encoded.size();return false;}
    keys.insert(keys.end(),encoded.begin(),encoded.end());return true;
  }
  uint8_t read(unsigned reg) const {
    if(reg==0)return keys.empty()?0:keys.front();
    if(reg==1)return (keyboard_control&0x7f)|(keys.empty()?0:0x80);
    if(reg==2)return 0; // immediate display acknowledgment, bit 7 clear
    return display_control;
  }
  void consume(){if(!keys.empty())keys.pop_front();}
  void write(unsigned reg,uint8_t value) {
    if(reg==1)keyboard_control=value;
    if(reg==3)display_control=value;
    if(reg!=2)return;
    unsigned char c=value&0x7f;
    // Before data mode the original PIA setup writes its direction register.
    if(!(display_control&4))return;
    if(c=='\r'||c=='\n') {transcript+='\n';lines.emplace_back();}
    else if(c==8||c==127||c=='_') {if(!lines.back().empty())lines.back().pop_back();}
    else if(c>=32&&c<127) {
      transcript+=char(c);
      if(lines.back().size()>=40)lines.emplace_back();
      lines.back()+=char(c);
    }
    while(lines.size()>history_limit)lines.pop_front();
    if(transcript.size()>transcript_limit)transcript.erase(0,transcript.size()-transcript_limit);
  }
  void clear(){lines={std::string{}};transcript.clear();}
};
}
