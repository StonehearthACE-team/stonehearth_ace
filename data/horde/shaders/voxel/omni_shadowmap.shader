[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;

in vec3 vertPos;

out vec3 worldPos;

void main(void)
{
  vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
  worldPos = pos.xyz;
  gl_Position = viewProjMat * pos;
}


[[FS]]
#version 410
out vec4 fragColor;
uniform vec4 lightPos;
in vec3 worldPos;

void main(void)
{
  fragColor.r = length(worldPos - lightPos.xyz);
}
