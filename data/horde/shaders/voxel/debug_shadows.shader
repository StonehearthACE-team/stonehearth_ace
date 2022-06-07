[[FX]]


[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform mat4 shadowMats[4];
uniform mat4 fowViewMat;

in vec3 vertPos;

out vec4 pos;

out vec4 projShadowPos[3];

// out vec4 projFowPos;

void main( void )
{
  pos = calcWorldPos(vec4(vertPos, 1.0));
  vec4 vsPos = calcViewPos(pos);

  projShadowPos[0] = shadowMats[0] * pos;
  projShadowPos[1] = shadowMats[1] * pos;
  projShadowPos[2] = shadowMats[2] * pos;

  // projFowPos = fowViewMat * pos;

  gl_Position = viewProjMat * pos;
}


[[FS]]
#version 410
out vec4 fragColor;
in vec4 projShadowPos[3];
#include "shaders/shadows.shader"
in vec4 pos;


void main( void )
{
  fragColor = vec4(getCascadeColor(pos.xyz), 1.0);
}