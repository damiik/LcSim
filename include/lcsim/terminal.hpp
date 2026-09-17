#pragma once
#include <algorithm>
#include <cstdint>
#include <deque>
#include <string>
#include <vector>
namespace lc {

// Polling Apple-1/ACIA register interfaces, not complete 6820/6551 chips.
// Fixed 40x24 screen grid + minimal VT100/ANSI subset so 65C02 software can
// repaint the display: CUP (H/f), ED (J), EL (K), CUU/CUD/CUF/CUB (A-D),
// CNL/CPL (E/F), CHA (G), save/restore (s/u, ESC 7/8), RIS (ESC c), ^L.
class Terminal {
public:
  explicit Terminal(bool acia_mode=false):acia(acia_mode){
    screen.assign(rows,std::string(columns,' '));
  }
  bool acia=false;
  static constexpr size_t columns=40,rows=24;
  static constexpr size_t input_limit=4096, transcript_limit=65536;
  std::deque<uint8_t> keys;
  std::vector<std::string> screen;   // visible 24x40 grid, space padded
  std::string transcript;            // flat log, used by COPY
  size_t cursor_x=0,cursor_y=0;
  uint8_t keyboard_control=0,display_control=0;
  size_t dropped=0;
  bool crt=true;                     // GUI: scanlines/glow/flicker toggle
  bool cursor_visible=true;  
private:
  int esc_state=0;
  std::string esc_params;
  bool esc_private=false;            // remembers a leading '?' in CSI (e.g. ?25l)
  size_t saved_x=0,saved_y=0;
  bool last_nl=false;                    // absorbs CR,LF / LF,CR pairs
public:

  bool send(const std::string& text) {
    std::vector<uint8_t> encoded;
    bool cr=false;
    for(unsigned char c:text) {
      if(c=='\n'&&cr){cr=false;continue;}   // CRLF -> jedno LF
      cr=c=='\r';
      if(c=='\r')c='\n';                    // normalizacja: CR i LF -> LF (Linux)
      // if(c>='a'&&c<='z')c-=32;           // normalizacja: małe litery -> duże (Apple-1/WozMon)
      if(c==8||c==127)c=acia?8:'_';
      if(c==8||c=='\n'||c==27||(c>=32&&c<127))encoded.push_back(acia?c:c|0x80);
    }
    if(keys.size()+encoded.size()>input_limit){dropped+=encoded.size();return false;}
    keys.insert(keys.end(),encoded.begin(),encoded.end());return true;
  }
  // Wklejanie tekstow (pliki HEX/komendy): gwarantuje koncowy LF, zeby
  // loader Intel HEX rozpoznal koniec ostatniego rekordu. Wywolywac
  // z handlera wklejania zamiast send().
  bool paste(const std::string& text) {
    std::string t=text;
    if(!t.empty() && t.back()!='\n' && t.back()!='\r') t+='\n';
    return send(t);
  }
  uint8_t read(unsigned reg) const {
    if(acia) {
      if(reg==0)return keys.empty()?0:keys.front();
      if(reg==1)return 0x10|(keys.empty()?0:0x08);
      return reg==2?keyboard_control:display_control;
    }
    if(reg==0)return keys.empty()?0:keys.front();
    if(reg==1)return (keyboard_control&0x7f)|(keys.empty()?0:0x80);
    if(reg==2)return 0; // immediate display acknowledgment, bit 7 clear
    return display_control;
  }
  void consume(){if(!keys.empty())keys.pop_front();}

  void clear(){
    screen.assign(rows,std::string(columns,' '));
    transcript.clear();
    cursor_x=cursor_y=0;
    esc_state=0;
    esc_private=false;
    cursor_visible=true;
    last_nl=false;
  }

  void write(unsigned reg,uint8_t value) {
    if(acia) {
      if(reg==1){keys.clear();keyboard_control=0;}
      if(reg==2)keyboard_control=value;
      if(reg==3)display_control=value;
      if(reg!=0)return;
    }
    else {
      if(reg==1)keyboard_control=value;
      if(reg==3)display_control=value;
      if(reg!=2)return;
    }
    unsigned char c=value&0x7f;
    // Before data mode the original PIA setup writes its direction register.
    if(!acia&&!(display_control&4))return;
    put_char(c);
    if(transcript.size()>transcript_limit)transcript.erase(0,transcript.size()-transcript_limit);
  }

private:
  void newline()  {                      // next row, scroll at bottom
    transcript+='\n';
    cursor_x=0;
    if(++cursor_y>=rows)  {
      cursor_y=rows-1;
      screen.erase(screen.begin());
      screen.push_back(std::string(columns,' '));
    }
  }
  void put_char(unsigned char c)  {
    if(esc_state==1)  {
      esc_state=0;
      if(c=='['){esc_state=2; esc_params.clear(); esc_private=false; return;}
      if(c=='7'){saved_x=cursor_x;saved_y=cursor_y;return;}
      if(c=='8'){cursor_x=saved_x;cursor_y=saved_y;return;}
      if(c=='c'){clear();return;}
      return;
    }
    if(esc_state==2)  {
      if((c>='0'&&c<='9')||c==';'){esc_params+=char(c);return;}
      if(c=='?'){esc_private=true;return;}
      if(c==' '||c=='?'||c=='<'||c=='='||c=='>')return;
      esc_state=0;
      csi(char(c));
      return;
    }
    switch(c)  {
      case 27: esc_state=1; last_nl=false; break;
      case '\r':                         // Apple-1/WozMon: CR = start of NEXT line
        newline(); last_nl=true; break;
      case '\n':                         // firmware sending CRLF: count once
        if(!last_nl)newline();
        last_nl=true; break;
      case 12: clear(); break;           // ^L
      case 8: case 127:                  // BS/DEL: move only, no erase
        if(cursor_x)--cursor_x;
        last_nl=false; break;
      default:
        last_nl=false;
        if(c=='_'&&!acia){if(cursor_x)--cursor_x;break;}   // WozMon BS echo
        if(c<32||c>126)break;
        screen[cursor_y][cursor_x]=char(c);
        transcript+=char(c);
        if(++cursor_x>=columns)newline();                  // auto-wrap
    }
  }

  std::vector<int> csi_numbers() const {
    std::vector<int> out{0};
    for(char ch:esc_params) {
      if(ch==';')out.push_back(0);
      else if(ch>='0'&&ch<='9')out.back()=out.back()*10+(ch-'0');
    }
    return out;
  }
  void csi(char final_byte) {
    auto p=csi_numbers();
    auto arg=[&](size_t i){return p.size()>i&&p[i]>0?p[i]:1;}; // default 1
    switch(final_byte) {
      case 'H': case 'f':                    // CUP, 1-based row;col
        cursor_y=size_t(std::clamp(arg(0),1,int(rows))-1);
        cursor_x=size_t(std::clamp(arg(1),1,int(columns))-1);
        break;
      case 'A': cursor_y=size_t(std::max(0,int(cursor_y)-arg(0))); break;
      case 'B': cursor_y=std::min(rows-1,cursor_y+size_t(arg(0))); break;
      case 'C': cursor_x=std::min(columns-1,cursor_x+size_t(arg(0))); break;
      case 'D': cursor_x=size_t(std::max(0,int(cursor_x)-arg(0))); break;
      case 'E': cursor_y=std::min(rows-1,cursor_y+size_t(arg(0))); cursor_x=0; break;
      case 'F': cursor_y=size_t(std::max(0,int(cursor_y)-arg(0))); cursor_x=0; break;
      case 'G': case '`': cursor_x=size_t(std::clamp(arg(0),1,int(columns))-1); break;
      case 'K': {                            // EL: 0 right, 1 left, 2 line
        auto& row=screen[cursor_y];
        if(p[0]==0)std::fill(row.begin()+cursor_x,row.end(),' ');
        else if(p[0]==1)std::fill(row.begin(),row.begin()+cursor_x+1,' ');
        else std::fill(row.begin(),row.end(),' ');
        break;
      }
      case 'J': {                            // ED: 0 below, 1 above, 2 all
        if(p[0]==2||p[0]==3){for(auto& r:screen)std::fill(r.begin(),r.end(),' ');break;}
        if(p[0]==1) {
          for(size_t y=0;y<cursor_y;y++)std::fill(screen[y].begin(),screen[y].end(),' ');
          std::fill(screen[cursor_y].begin(),screen[cursor_y].begin()+cursor_x+1,' ');
        } else {
          std::fill(screen[cursor_y].begin()+cursor_x,screen[cursor_y].end(),' ');
          for(size_t y=cursor_y+1;y<rows;y++)std::fill(screen[y].begin(),screen[y].end(),' ');
        }
        break;
      }
      case 's': saved_x=cursor_x;saved_y=cursor_y; break;
      case 'u': cursor_x=saved_x;cursor_y=saved_y; break;
      case 'h': case 'l':
        if(esc_private&&p[0]==25)cursor_visible=(final_byte=='h'); 
        break;
      default: break;                        // m/h/l etc. ignored
    }
  }
};
}
