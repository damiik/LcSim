#version 330

in vec2 fragTexCoord;
out vec4 fragColor;

uniform sampler2D texture0;
uniform vec2  uSize;    // rozmiar ekranu terminala w px
uniform float uRadius;  // promień zaokrąglenia rogu w px
uniform float uCurve;   // 0.0 = płasko, ~0.06 = lekkie wygięcie CRT

float sdRoundBox(vec2 p,vec2 b,float r)  {
  vec2 q=abs(p)-b+r;
  return min(max(q.x,q.y),0.0)+length(max(q,0.0))-r;
}

void main()  {
  vec2 uv=fragTexCoord;

  if(uCurve>0.0)  {
    vec2 c=uv*2.0-1.0;
    c*=1.0+uCurve*dot(c,c);          // wybrzuszenie (barrel distortion)
    uv=c*0.5+0.5;
  }

  if(uv.x<0.0||uv.x>1.0||uv.y<0.0||uv.y>1.0)  { fragColor=vec4(0.0);return; }

  float d=sdRoundBox(uv*uSize,uSize*0.5,uRadius);
  float mask=1.0-smoothstep(-1.5,1.5,d);
  //float mask=1.0-smoothstep(-1.0,1.0,d);

  vec4 tex=texture(texture0,uv);

  // delikatna winieta, żeby krzywizna była bardziej czytelna
  vec2 vc=uv*2.0-1.0;
  float vignette=1.0-0.18*dot(vc,vc);

  fragColor=vec4(tex.rgb*vignette,tex.a*mask);
}
