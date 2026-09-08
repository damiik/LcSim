#include <lcsim/gui.hpp>
#include <lcsim/scope.hpp>
#include <raylib.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <iomanip>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
namespace lc  {
  namespace  {
    Font ui_font{};
    bool ui_font_loaded=false;
    constexpr float ui_text_scale=2.f;
    const Color bg  {
      15,20,27,255
    },panel  {
      27,35,46,255
    },line  {
      63,79,99,255
    },fg  {
      216,223,232,255
    },muted  {
      142,160,183,255
    },green  {
      64,211,153,255
    },blue  {
      72,153,245,255
    };
    void text(const std::string& value,float x,float y,float size,Color tint)  {
      size*=ui_text_scale;
      if(ui_font_loaded)DrawTextEx(ui_font,value.c_str(),{x,y},size,0.5f,tint);
      else DrawText(value.c_str(),int(x),int(y),int(size),tint);
    }
    void text(const char* value,float x,float y,float size,Color tint)  {
      text(std::string(value),x,y,size,tint);
    }
    bool button(Rectangle r,const std::string& label,bool selected=false)  {
      bool hover=CheckCollisionPointRec(GetMousePosition(),r);
      DrawRectangleRec(r,selected?green:hover?Color  {
        58,76,97,255
      }
      :panel);
      DrawRectangleLinesEx(r,1,line);
      float by_width=(r.width-12)/(std::max<size_t>(1,label.size())*.62f*ui_text_scale);
      float size=std::max(5.f,std::min({16.f,(r.height-6)/ui_text_scale,by_width}));
      text(label,r.x+7,r.y+(r.height-size*ui_text_scale)/2,size,selected?bg:fg);
      return hover&&IsMouseButtonPressed(MOUSE_BUTTON_LEFT);
    }
    std::string number(double n)  {
      char b[64];
      std::snprintf(b,sizeof(b),"%.3g",n);
      return b;
    }
    Color color(const std::string& s,Color fallback)  {
      try  {
        if(s.size()==7&&s[0]=='#')return GetColor(static_cast<unsigned>(std::stoul(s.substr(1),nullptr,16)<<8)|255);
      }
      catch(...)  {}
      return fallback;
    }
    std::string display_value(const Simulator& sim,const Probe& p)  {
      auto bits=sim.bits(p);
      if(bits.find_first_not_of("01")!=std::string::npos)return sim.hex(p);
      if(p.visual.mode=="hex")return sim.hex(p);
      uint64_t word=std::stoull(bits,nullptr,2);
      if(p.visual.mode=="dec")return std::to_string(word);
      if(p.visual.mode=="ascii")  {
        std::string text;
        for(size_t b=0; b<(bits.size()+7)/8; b++)  {
          char ch=char((word>>(8*b))&255);
          text+=ch>=32&&ch<127?ch:'.';
        }
        return text;
      }
      return sim.hex(p);
    }
    std::string format_bits(const std::string& s)  {
      if(s.find('x')!=std::string::npos)return "X";
      if(s.find('z')!=std::string::npos)return "Z";
      if(s.size()==1)return s;
      std::string out;
      for(size_t end=s.size();
      end;
      )  {
        size_t start=end>=4?end-4:0;
        out.insert(out.begin(),"0123456789ABCDEF"[std::stoi(s.substr(start,end-start),nullptr,2)]);
        end=start;
      }
      return "0x"+out;
    }
    uint64_t memory_number(const std::string& token)  {
      int base=16;
      size_t offset=0;
      if(token.size()>2&&token[0]=='0')  {
        if(token[1]=='x'||token[1]=='X'){base=16;offset=2;}
        else if(token[1]=='b'||token[1]=='B'){base=2;offset=2;}
        else if(token[1]=='o'||token[1]=='O'){base=8;offset=2;}
      }
      size_t used=0;
      auto value=std::stoull(token.substr(offset),&used,base);
      if(used!=token.size()-offset)throw std::runtime_error("invalid memory token: "+token);
      return value;
    }
    std::vector<uint64_t> parse_memory_image(const std::string& source,size_t limit)  {
      std::vector<uint64_t> result;
      std::istringstream lines(source);
      std::string line_text;
      size_t cursor=0;
      while(std::getline(lines,line_text))  {
        size_t comment=line_text.size();
        for(const auto& marker:{std::string("//"),std::string("#"),std::string(";")})  {
          auto found=line_text.find(marker);
          if(found!=std::string::npos)comment=std::min(comment,found);
        }
        line_text.resize(comment);
        std::replace(line_text.begin(),line_text.end(),',',' ');
        std::istringstream tokens(line_text);
        std::string token;
        while(tokens>>token)  {
          if(token.front()=='@')  {
            cursor=static_cast<size_t>(memory_number(token.substr(1)));
            if(cursor>=limit)throw std::runtime_error("memory address exceeds device depth");
            if(result.size()<cursor)result.resize(cursor,0);
            continue;
          }
          if(cursor>=limit)throw std::runtime_error("memory image exceeds device depth");
          if(result.size()<=cursor)result.resize(cursor+1,0);
          result[cursor++]=memory_number(token);
        }
      }
      return result;
    }
    std::string memory_hex(uint64_t value,unsigned bits)  {
      std::ostringstream out;
      out<<std::uppercase<<std::hex<<std::setfill('0')<<std::setw(std::max(1u,(bits+3)/4))<<value;
      return out.str();
    }
    bool scope_probe(const Probe& p)  {
      return !p.visual.pixel&&(p.visual.type=="NODE"||p.visual.type=="INPUT"||p.visual.type=="INOUT"||p.visual.type=="BUS");
    }
    void draw_scope_probe_list(Scope& scope,const Simulator& sim,Rectangle side,int& scroll)  {
      const auto mouse=GetMousePosition();
      if(CheckCollisionPointRec(mouse,side))scroll=std::max(0,scroll-int(GetMouseWheelMove()*3));
      text("CHANNELS",side.x+14,side.y+12,12,muted);
      text("Select NODE/INPUT signals",side.x+14,side.y+31,11,muted);
      BeginScissorMode(int(side.x),int(side.y+52),int(side.width),int(side.height-52));
      int row=0;
      for(const auto& p:sim.probes())  {
        if(!scope_probe(p))continue;
        float y=side.y+58+float(row++-scroll)*29;
        if(y<side.y+45||y>side.y+side.height)continue;
        Rectangle box{side.x+14,y,18,18};
        bool checked=scope.has_channel(p.name);
        DrawRectangleLinesEx(box,1,checked?green:line);
        if(checked)DrawRectangleRec({box.x+4,box.y+4,10,10},green);
        text(p.name,box.x+28,y+1,12,fg);
        if(CheckCollisionPointRec(mouse,{side.x,y,side.width,25})&&IsMouseButtonPressed(MOUSE_BUTTON_LEFT))  {
          if(checked)scope.remove_channel([&](){for(size_t i=0;i<scope.channels.size();i++)if(scope.channels[i].probe.name==p.name)return i;return scope.channels.size();}());
          else scope.add_channel(p.name);
        }
      }
      EndScissorMode();
    }
    void draw_memory_panel(Simulator& sim,Rectangle side,std::string& selected,int& scroll,
                           std::map<std::string,std::vector<uint64_t>>& overrides,std::string& status)  {
      auto memories=sim.memory_info();
      if(memories.empty())  {
        text("No ROM or RAM",side.x+12,side.y+12,11,muted);
        return;
      }
      if(std::none_of(memories.begin(),memories.end(),[&](const MemoryInfo& m){return m.name==selected;}))selected=memories.front().name;
      float y=side.y+8;
      for(const auto& memory:memories)  {
        if(button({side.x+8,y,side.width-16,34},memory.type+" "+memory.name,memory.name==selected))  {
          selected=memory.name;
          scroll=0;
        }
        y+=38;
      }
      auto it=std::find_if(memories.begin(),memories.end(),[&](const MemoryInfo& m){return m.name==selected;});
      if(it==memories.end())return;
      y+=4;
      if(button({side.x+8,y,108,34},"PASTE"))  {
        try  {
          const char* clipboard=GetClipboardText();
          if(!clipboard)throw std::runtime_error("clipboard is empty");
          auto words=parse_memory_image(clipboard,it->words);
          sim.replace_memory(selected,words);
          overrides[selected]=words;
          status="Loaded "+std::to_string(words.size())+" words into "+selected;
        }
        catch(const std::exception& e){status=e.what();}
      }
      if(button({side.x+124,y,108,34},"CLEAR"))  {
        try  {
          sim.clear_memory(selected);
          overrides[selected]={};
          status="Cleared "+selected;
        }
        catch(const std::exception& e){status=e.what();}
      }
      y+=43;
      text(it->type+"  "+std::to_string(it->words)+" words",side.x+10,y,10,muted);
      y+=25;
      Rectangle browser{side.x+5,y,side.width-10,side.y+side.height-y};
      if(CheckCollisionPointRec(GetMousePosition(),browser))scroll=std::max(0,scroll-int(GetMouseWheelMove()*4));
      int visible=std::max(1,int(browser.height/27));
      scroll=std::clamp(scroll,0,std::max(0,int(it->words)-visible));
      BeginScissorMode(int(browser.x),int(browser.y),int(browser.width),int(browser.height));
      unsigned address_bits=std::max(1u,it->address_width);
      for(int row=0;row<visible&&scroll+row<int(it->words);row++)  {
        size_t address=static_cast<size_t>(scroll+row);
        text(memory_hex(address,address_bits)+": "+memory_hex(sim.memory_word(selected,address),it->data_width),browser.x+6,browser.y+row*27,10,address%2?fg:green);
      }
      EndScissorMode();
    }
    void draw_scope(Scope& scope,Simulator& sim,Rectangle area,double& pan,int& scroll,Time& cursorA,Time& cursorB)  {
      float x=area.x+190,w=area.width-200,y=area.y+65;
      if(button(  {
        area.x+8,area.y+7,85,30
      },scope.mode==Scope::Auto?"AUTO":scope.mode==Scope::Normal?"NORMAL":"SINGLE"))  {
        scope.mode=static_cast<Scope::Mode>((scope.mode+1)%3);
        scope.arm();
      }
      if(button(  {
        area.x+101,area.y+7,70,30
      },"ARM"))scope.arm();
      if(button(  {
        area.x+180,area.y+7,70,30
      },scope.both_edges?"BOTH":scope.rising?"RISE":"FALL")){if(scope.both_edges){scope.both_edges=false;scope.rising=true;}else if(scope.rising)scope.rising=false;else scope.both_edges=true;}
      if(button(  {
        area.x+260,area.y+7,100,30
      },"BIT "+std::to_string(scope.trigger_bit)))scope.trigger_bit=(scope.trigger_bit+1)%int(scope.trigger_channel>=0?scope.channels[scope.trigger_channel].probe.nets.size():1);
      if(button(  {
        area.x+370,area.y+7,150,30
      },"Hold "+number(scope.holdoff/1000.)+" ns"))scope.holdoff=scope.holdoff==0?100000:scope.holdoff==100000?1000000:0;
      if(button(  {
        area.x+530,area.y+7,105,30
      },"Pre "+number(scope.pretrigger*100)+"%"))scope.pretrigger=scope.pretrigger<.8?scope.pretrigger+.1:0;
      text("Wheel: zoom | Shift+wheel: channels | drag: pan | left/right: cursors | click label: trigger",area.x+8,area.y+43,12,muted);
      Vector2 mouse=GetMousePosition();
      if(CheckCollisionPointRec(mouse,area))  {
        float wheel=GetMouseWheelMove();
        if(IsKeyDown(KEY_LEFT_SHIFT))scroll=std::max(0,scroll-int(wheel));
        else if(wheel!=0)scope.span=std::clamp<Time>(static_cast<Time>(scope.span*std::pow(1.25,-wheel)),1000,1000000000000LL);
        if(IsMouseButtonDown(MOUSE_BUTTON_MIDDLE))pan-=GetMouseDelta().x/w*scope.span;
      }
      Time right=scope.trigger_time>=0&&scope.mode!=Scope::Auto?scope.trigger_time+static_cast<Time>(scope.span*(1-scope.pretrigger)):sim.now;
      Time start=std::max<Time>(0,right-scope.span+static_cast<Time>(pan));
      if(mouse.x>x&&mouse.y>y&&CheckCollisionPointRec(mouse,area))  {
        Time t=start+static_cast<Time>((mouse.x-x)/w*scope.span);
        if(IsMouseButtonPressed(MOUSE_BUTTON_LEFT))cursorA=t;
        if(IsMouseButtonPressed(MOUSE_BUTTON_RIGHT))cursorB=t;
      }
      BeginScissorMode(int(area.x),int(y),int(area.width),int(area.height-65));
      for(int k=0; k<=10; k++)  {
        float gx=x+k*w/10;
        DrawLine(int(gx),int(y),int(gx),int(area.y+area.height),line);
        text(number((start+scope.span*k/10)/1000.)+" ns",gx+3,y,10,muted);
      }
      for(size_t ci=static_cast<size_t>(scroll);
      ci<scope.channels.size();
      ci++)  {
        float row=y+25+float(ci-scroll)*56;
        if(row>area.y+area.height)break;
        const auto& c=scope.channels[ci];
        Color ink=ci%3==0?green:ci%3==1?blue:Color  {
          240,199,74,255
        };
        Rectangle label  {
          area.x,row,185,50
        };
        if(CheckCollisionPointRec(mouse,label)&&IsMouseButtonPressed(MOUSE_BUTTON_LEFT))  {
          scope.trigger_channel=int(ci);
          scope.arm();
        }
        text(c.probe.name,area.x+8,row+4,13,scope.trigger_channel==int(ci)?green:fg);
        if(button({area.x+92,row+2,25,20},"^"))scope.move_channel(ci,-1);
        if(button({area.x+120,row+2,25,20},"v"))scope.move_channel(ci,1);
        if(button({area.x+148,row+2,25,20},"x"))  {
          scope.remove_channel(ci);
          break;
        }
        text(format_bits(scope.at(ci,sim.now)),area.x+8,row+25,14,ink);
        auto draw=[&](Time a,Time b,const std::string& bits)  {
          float aX=x+float(double(a-start)/scope.span*w),bX=x+float(double(b-start)/scope.span*w);
          aX=std::max(x,aX);
          bX=std::min(x+w,bX);
          if(bX<aX)return;
          auto dashed=[&](float level,Color shade)  {
            for(float px=aX;px<bX;px+=10)DrawLineEx({px,level},{std::min(px+6,bX),level},2,shade);
          };
          if(bits.size()>1)  {
            float top=row+9,bottom=row+37,middle=(top+bottom)/2,tip=std::min(7.f,(bX-aX)/2);
            Color bus_ink=bits.find('x')!=std::string::npos?RED:bits.find('z')!=std::string::npos?muted:ink;
            if(bits.find('z')!=std::string::npos)dashed(middle,bus_ink);
            else  {
              DrawLineEx({aX,middle},{aX+tip,top},2,bus_ink);
              DrawLineEx({aX,middle},{aX+tip,bottom},2,bus_ink);
              DrawLineEx({aX+tip,top},{bX-tip,top},2,bus_ink);
              DrawLineEx({aX+tip,bottom},{bX-tip,bottom},2,bus_ink);
              DrawLineEx({bX-tip,top},{bX,middle},2,bus_ink);
              DrawLineEx({bX-tip,bottom},{bX,middle},2,bus_ink);
            }
            if(bX-aX>58)text(format_bits(bits),aX+tip+3,row+12,11,bus_ink);
          }
          else  {
            float level=row+(bits=="1"?8:bits=="0"?37:23);
            if(bits=="z")dashed(level,muted);
            else DrawLineEx({aX,level},{bX,level},2,bits=="x"?RED:ink);
            if(bits!="z")DrawLine(int(aX),int(row+8),int(aX),int(row+37),bits=="x"?RED:ink);
          }
        };
        Time last=start;
        auto bits=scope.at(ci,start);
        for(const auto& s:c.samples)  {
          if(s.time<=start)continue;
          if(s.time>start+scope.span)break;
          draw(last,s.time,bits);
          last=s.time;
          bits=s.bits;
        }
        draw(last,start+scope.span,bits);
      }
      for(Time t:  {
        cursorA,cursorB
      }
      )if(t>=start&&t<=start+scope.span)  {
        int px=int(x+double(t-start)/scope.span*w);
        DrawLine(px,int(y),px,int(area.y+area.height),WHITE);
      }
      EndScissorMode();
      text("dt: "+number(std::abs(cursorB-cursorA)/1000.)+" ns | "+(scope.frozen?"CAPTURED":scope.trigger_time<0?"WAITING":"TRIGGERED"),x+10,area.y+area.height-18,12,fg);
    }
  }
  int gui(const Design& design,Profile profile,bool scope_first,bool cache)  {
    SetConfigFlags(FLAG_WINDOW_RESIZABLE);
    InitWindow(1440,900,("LcSim - "+design.name).c_str());
    SetTargetFPS(60);
    SetExitKey(KEY_F10);
    const char* font_paths[]={"assets/fonts/MapleMono-Regular.ttf","../assets/fonts/MapleMono-Regular.ttf"};
    for(const auto* path:font_paths)if(FileExists(path))  {
      ui_font=LoadFontEx(path,64,nullptr,0);
      ui_font_loaded=ui_font.texture.id!=0;
      if(ui_font_loaded)SetTextureFilter(ui_font.texture,TEXTURE_FILTER_BILINEAR);
      break;
    }
    auto sim=std::make_unique<Simulator>(design,profile,cache);
    sim->cache_enabled=cache;
    auto scope=std::make_unique<Scope>(*sim,design.scope);
    scope->configure(design.scope_config);
    bool running=true,show_scope=scope_first,memory_tab=false;
    int sidebar_scroll=0,memory_scroll=0,scope_scroll=0;
    double target=1000,accumulator=0,actual=0,pan=0;
    Time cursorA=0,cursorB=0;
    std::string status="ready",editing,edit_value,selected_memory;
    std::map<std::string,std::vector<uint64_t>> memory_overrides;
    while(!WindowShouldClose())  {
      double frame=GetFrameTime();
      if(running)  {
        accumulator+=frame*target;
        auto begin=GetTime();
        uint64_t count=0;
        while(accumulator>=1&&GetTime()-begin<.008)  {
          sim->step();
          accumulator--;
          count++;
        }
        accumulator=std::min(accumulator,target*.1);
        actual=.9*actual+.1*count/std::max(frame,.00001);
      }
      scope->poll(sim->now);
      BeginDrawing();
      ClearBackground(bg);
      int width=GetScreenWidth(),height=GetScreenHeight();
      DrawRectangle(0,0,width,90,panel);
      DrawText("LcSim",18,10,46,fg);
      text(design.name,18,60,14,muted);
      if(button(  {
        260,22,90,48
      },running?"PAUSE":"RUN",running))running=!running;
      if(button(  {
        360,22,70,48
      },"STEP"))  {
        running=false;
        sim->step();
      }
      auto reset=[&]()  {
        scope.reset();
        sim=std::make_unique<Simulator>(design,profile,cache);
        sim->cache_enabled=cache;
        for(const auto& [name,words]:memory_overrides)sim->replace_memory(name,words);
        scope=std::make_unique<Scope>(*sim,design.scope);
        scope->configure(design.scope_config);
        pan=0;
        accumulator=0;
      };
      if(button(  {
        440,22,80,48
      },"RESET"))reset();
      if(button(  {
        530,22,110,48
      },"AUTO CLK",sim->auto_clock))sim->auto_clock=!sim->auto_clock;
      if(button(  {
        650,22,90,48
      },profile.name))  {
        profile=profile.name=="LVC"?Profile::fpga():Profile::lvc();
        reset();
      }
      if(button(  {
        750,22,95,48
      },show_scope?"PANELS":"SCOPE"))show_scope=!show_scope;
      Rectangle slider  {
        865,60,240,6
      };
      DrawRectangleRec(slider,line);
      float pos=float(std::log10(target)/7);
      DrawCircle(int(slider.x+pos*slider.width),63,6,blue);
      if(IsMouseButtonDown(MOUSE_BUTTON_LEFT)&&CheckCollisionPointRec(GetMousePosition(),  {
        slider.x,45,slider.width,35
      }
      ))target=std::pow(10,std::clamp((GetMouseX()-slider.x)/slider.width,0.f,1.f)*7);
      text("TARGET "+number(target)+" steps/s  ACTUAL "+number(actual),865,20,12,muted);
      int side_width=show_scope?245:0;
      Rectangle side{0,91,float(side_width),float(height-139)};
      if(show_scope)  {
        DrawRectangleRec(side,panel);
        DrawLine(side_width,91,side_width,height-48,line);
        if(button({side.x+8,side.y+7,111,34},"CHANNELS",!memory_tab))memory_tab=false;
        if(button({side.x+126,side.y+7,111,34},"MEMORY",memory_tab))memory_tab=true;
        Rectangle side_content{side.x,side.y+47,side.width,side.height-47};
        if(memory_tab)draw_memory_panel(*sim,side_content,selected_memory,memory_scroll,memory_overrides,status);
        else draw_scope_probe_list(*scope,*sim,side_content,sidebar_scroll);
      }
      Rectangle workspace  {
        show_scope?float(side_width+15):15.f,100,
        float(width-(show_scope?side_width+30:30)),float(height-160)
      };
      if(!editing.empty())  {
        int ch;
        while((ch=GetCharPressed())>0)if(edit_value.size()<66&&ch>=32&&ch<127)edit_value+=char(ch);
        if(IsKeyPressed(KEY_BACKSPACE)&&!edit_value.empty())edit_value.pop_back();
        if(IsKeyPressed(KEY_ESCAPE))editing.clear();
        if(IsKeyPressed(KEY_ENTER))  {
          try  {
            sim->drive(editing,edit_value);
            editing.clear();
          }
          catch(const std::exception& e)  {
            status=e.what();
          }
        }
        DrawRectangleRec({workspace.x+8,workspace.y+8,260,35},bg);
        text(editing+" = "+edit_value,workspace.x+12,workspace.y+16,14,fg);
      }
      DrawRectangle(0,height-48,width,48,panel);
      text("time "+number(sim->now/1000.)+" ns | tick "+number(profile.tick/1000.)+" ns",15,height-38,12,fg);
      text("gates "+std::to_string(sim->gate_count())+" | events "+std::to_string(sim->stats.events),300,height-38,12,muted);
      text("cache "+std::to_string(sim->stats.hits)+" / "+std::to_string(sim->stats.misses),560,height-38,12,muted);
      text(status,800,height-38,12,green);
      if(show_scope)  {
        draw_scope(*scope,*sim,workspace,pan,scope_scroll,cursorA,cursorB);
        try  {
          if(IsKeyPressed(KEY_V)||button({workspace.x+650,workspace.y+7,70,30},"VCD"))  {
            scope->export_vcd("capture.vcd",IsKeyDown(KEY_LEFT_SHIFT)?std::min(cursorA,cursorB):scope->available_begin(),IsKeyDown(KEY_LEFT_SHIFT)?std::max(cursorA,cursorB):sim->now);
            status="Saved capture.vcd";
          }
          if(IsKeyPressed(KEY_C)||button({workspace.x+730,workspace.y+7,70,30},"CSV"))  {
            scope->export_csv("capture.csv",IsKeyDown(KEY_LEFT_SHIFT)?std::min(cursorA,cursorB):scope->available_begin(),IsKeyDown(KEY_LEFT_SHIFT)?std::max(cursorA,cursorB):sim->now);
            status="Saved capture.csv";
          }
        }
        catch(const std::exception& e)  {
          status=e.what();
        }
      }
      else  {
        DrawText("Main workspace",int(workspace.x+8),int(workspace.y+8),28,muted);
        size_t input_index=0;
        for(const auto& p:sim->probes())  {
          if(!p.input)continue;
          float card_x=workspace.x+8+float(input_index%4)*205;
          float card_y=workspace.y+34+float(input_index/4)*68;
          ++input_index;
          DrawRectangleRec({card_x,card_y,194,58},panel);
          DrawRectangleLinesEx({card_x,card_y,194,58},1,line);
          text(p.name,card_x+8,card_y+6,12,blue);
          text(sim->hex(p),card_x+8,card_y+28,16,green);
          if(p.nets.size()==1)  {
            for(int b=0;b<3;b++)if(button({card_x+96+30.f*b,card_y+20,27,26},b==2?"Z":std::to_string(b)))  {
              sim->drive(p.name,b==2?"Z":std::to_string(b));
            }
          }
          else if(button({card_x+118,card_y+20,66,26},"EDIT"))  {
            editing=p.name;
            edit_value="0x";
          }
        }
        std::vector<const Probe*> outputs;
        double minx=1e30,maxx=-1e30,miny=1e30,maxy=-1e30;
        for(const auto& p:sim->probes())if(p.visual.pixel||p.visual.type=="OUTPUT"||p.visual.type=="DISPLAY")  {
          outputs.push_back(&p);
          minx=std::min(minx,p.visual.x);
          maxx=std::max(maxx,p.visual.x);
          miny=std::min(miny,p.visual.y);
          maxy=std::max(maxy,p.visual.y);
        }
        float input_rows=float((input_index+3)/4);
        double output_top=workspace.y+std::min(std::max(170.f,50.f+input_rows*68.f),workspace.height*.45f);
        double scale=std::min(std::max(1.,double(workspace.width-200))/std::max(1.,maxx-minx),std::max(1.,double(workspace.height-output_top-workspace.y-30))/std::max(1.,maxy-miny));
        for(const auto* p:outputs)  {
          float x=workspace.x+workspace.width/2+float((p->visual.x-(minx+maxx)/2)*scale),y=float(output_top+(workspace.height-(output_top-workspace.y))/2+(p->visual.y-(miny+maxy)/2)*scale);
          if(p->visual.pixel)  {
            Logic v=sim->value(p->nets[0]);
            Color ink=v==Logic::H?color(p->visual.on,green):v==Logic::L?color(p->visual.off,line):v==Logic::X?RED:muted;
            float size=float(std::clamp(p->visual.size*scale,3.,70.));
            if(p->visual.shape=="SQUARE"||p->visual.shape=="square"||p->visual.shape=="RECT")DrawRectangleRec(  {
              x-size/2,y-size/2,size,size
            },ink);
            else DrawCircleV(  {
              x,y
            },size/2,ink);
          }
          else  {
            DrawRectangleRec(  {
              x-90,y-45,180,90
            },panel);
            DrawRectangleLinesEx(  {
              x-90,y-45,180,90
            },1,line);
            text(p->name,x-78,y-32,13,muted);
            text(display_value(*sim,*p),x-65,y+1,28,green);
          }
        }
        if(outputs.empty())text("No OUTPUT, DISPLAY or styled NODE elements",workspace.x+25,workspace.y+125,18,muted);
      }
      EndDrawing();
    }
    scope.reset();
    if(ui_font_loaded)  {
      UnloadFont(ui_font);
      ui_font_loaded=false;
    }
    CloseWindow();
    return 0;
  }
}
