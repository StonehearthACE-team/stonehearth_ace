[[FX]]

sampler2D image = sampler_state
{
  Address = Clamp;
  Filter = None;
};

[[VS]]
#version 410
#include "shaders/fsquad_vs.glsl"

[[FS]]
#version 410
out vec4 fragColor;

in vec2 texCoords;
uniform sampler2D image;
uniform vec4 frameBufSize;

void main()
{
  vec4 color = vec4(0.0);

  vec2 off1 = vec2(0, 1.3846153846) * frameBufSize.zw;
  vec2 off2 = vec2(0, 3.2307692308) * frameBufSize.zw;
  color += texture(image, texCoords) * 0.2270270270;
  color += texture(image, texCoords + off1) * 0.3162162162;
  color += texture(image, texCoords - off1) * 0.3162162162;
  color += texture(image, texCoords + off2) * 0.0702702703;
  color += texture(image, texCoords - off2) * 0.0702702703;

  fragColor = color;
}
