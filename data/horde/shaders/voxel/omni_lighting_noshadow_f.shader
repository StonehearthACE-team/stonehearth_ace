[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform mat4 fowViewMat;

in vec3 vertPos;
in vec3 normal;
in vec3 color;

out vec4 pos;
out vec3 tsbNormal;
out vec3 albedo;

void main( void )
{
  pos = calcWorldPos(vec4(vertPos, 1.0));
  vec4 vsPos = calcViewPos(pos);
  tsbNormal = calcWorldVec(normal);
  albedo = color;

  gl_Position = viewProjMat * pos;
}


[[FS]]
#version 410
out vec4 fragColor;
#include "shaders/utilityLib/fragLighting.glsl"

uniform vec4 matDiffuseCol;
uniform vec4 matSpecParams;

in vec4 pos;
in vec3 albedo;
in vec3 tsbNormal;

void main( void )
{
  fragColor = vec4(calcSimpleOmniLight(pos.xyz, normalize(tsbNormal)) * albedo, 1.0);
}
