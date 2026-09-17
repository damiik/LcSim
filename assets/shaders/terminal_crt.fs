#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float virtPixelSize;

// Rozmiar wirtualnego piksela w fizycznych pikselach
const float VIRT_PIXEL_SIZE = 4.0;

void main()
{
    ivec2 texSize = textureSize(texture0, 0);
    vec2 virtRes = vec2(float(texSize.x), float(texSize.y));

    // Lekki filtr krawędziowy na obrazie wirtualnym usuwa migotanie cienkich
    // linii w ruchu. Mieszanie sąsiadów świadomie tworzy kolory pośrednie
    // spoza palety C64, zachowując jednocześnie jej kolory bazowe.
    vec2 texel = 1.0 / virtRes;
    vec4 center = texture(texture0, fragTexCoord);
    vec4 north = texture(texture0, fragTexCoord + vec2(0.0, -texel.y));
    vec4 south = texture(texture0, fragTexCoord + vec2(0.0, texel.y));
    vec4 east = texture(texture0, fragTexCoord + vec2(texel.x, 0.0));
    vec4 west = texture(texture0, fragTexCoord + vec2(-texel.x, 0.0));
    vec3 lumaWeights = vec3(0.299, 0.587, 0.114);
    float centerLuma = dot(center.rgb, lumaWeights);
    float minLuma = min(centerLuma, min(min(dot(north.rgb, lumaWeights),
      dot(south.rgb, lumaWeights)), min(dot(east.rgb, lumaWeights),
      dot(west.rgb, lumaWeights))));
    float maxLuma = max(centerLuma, max(max(dot(north.rgb, lumaWeights),
      dot(south.rgb, lumaWeights)), max(dot(east.rgb, lumaWeights),
      dot(west.rgb, lumaWeights))));
    float edge = maxLuma-minLuma;
    float blend = smoothstep(0.035, 0.28, edge)*0.31;
    vec4 texelColor = mix(center, (north+south+east+west)*0.25, blend);

    // Pozycja w obrębie wirtualnego piksela – w przestrzeni EKRANU
    // Dzięki gl_FragCoord wzorzec jest zawsze taki sam, niezależnie od rozdzielczości
    vec2 subPos = fract(gl_FragCoord.xy / VIRT_PIXEL_SIZE);

    // ---- SCANLINE ----
    // Wiersz 0 (top):    100% – jasne centrum fosforu
    // Wiersz 1:          100%
    // Wiersz 2:           70% – zanik
    // Wiersz 3 (bottom):  30% – szczelina między rzędami
    //
    // smoothstep daje płynne, krzywe przejście zamiast twardego cięcia


    // Pozycja w obrębie wirtualnego piksela [0.0 – 1.0]
    //float scanY = fract(gl_FragCoord.y / VIRT_PIXEL_SIZE);
    float scanY = fract(gl_FragCoord.y / virtPixelSize);

    float b0 = 0.88; // top    – rozjaśnianie
    float b1 = 1.00; // środek – centrum fosforu
    float b2 = 0.88; // zanik
    float b3 = 0.65; // bottom – szczelina

    float dim;
    if      (scanY < 0.25) dim = b0;
    else if (scanY < 0.50) dim = b1;
    else if (scanY < 0.75) dim = b2;
    else                   dim = b3;

    texelColor.rgb *= dim;



    // ---- PHOSPHOR SMEAR ----
    // Prawy piksel "wcieka" na prawą krawędź lewego wirtualnego piksela
    // vec4 nextColor = texture(texture0, fragTexCoord + vec2(texel.x, 0.0));

    // float scanX       = subPos.x;                          // 0.0 = lewa, 1.0 = prawa krawędź
    // float phosphor    = smoothstep(0.5, 1.0, scanX) * 0.5;
    // texelColor.rgb    = mix(texelColor.rgb, nextColor.rgb * dim, phosphor);

    finalColor = texelColor * colDiffuse;
}