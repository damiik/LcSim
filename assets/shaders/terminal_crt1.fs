#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Match the virtual-pixel CRT treatment used by the NIM game.
const float VIRT_PIXEL_SIZE = 4.0;

void main()
{
    ivec2 texSize = textureSize(texture0, 0);
    vec2 virtRes = vec2(float(texSize.x), float(texSize.y));
    vec2 texel = 1.0 / virtRes;

    // Fast CRT: keep scanlines and phosphor smear, without the
    // four extra edge-filter samples used by the full CRT shader.
    vec4 texelColor = texture(texture0, fragTexCoord);

    vec2 subPos = fract(gl_FragCoord.xy / VIRT_PIXEL_SIZE);

    float scanY = fract(gl_FragCoord.y / VIRT_PIXEL_SIZE);

    float b0 = 0.88;
    float b1 = 1.00;
    float b2 = 0.88;
    float b3 = 0.65;

    float dim;
    if      (scanY < 0.25) dim = b0;
    else if (scanY < 0.50) dim = b1;
    else if (scanY < 0.75) dim = b2;
    else                   dim = b3;

    texelColor.rgb *= dim;

    // Phosphor smear: the next virtual pixel bleeds into the right edge.
    // vec4 nextColor = texture(texture0, fragTexCoord + vec2(texel.x, 0.0));
    // float scanX = subPos.x;
    // float phosphor = smoothstep(0.5, 1.0, scanX) * 0.5;
    // texelColor.rgb = mix(texelColor.rgb, nextColor.rgb * dim, phosphor);

    finalColor = texelColor * colDiffuse;
}