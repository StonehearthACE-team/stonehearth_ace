[[FX]]

sampler2D outlineSampler = sampler_state
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
#include "shaders/utilityLib/outline.glsl"

uniform sampler2D outlineSampler;

in vec2 texCoords;

void main(void)
{
  fragColor = compute_outline_color(outlineSampler, texCoords);
}
