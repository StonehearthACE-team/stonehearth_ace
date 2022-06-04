[[FX]]

float4 flat_color;

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;

in vec3 vertPos;

void main( void )
{
  vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
  gl_Position = viewProjMat * pos;
}


[[FS]]
#version 410
out vec4 fragColor;

uniform vec4 flat_color;

void main(void)
{
  fragColor = flat_color;
}
