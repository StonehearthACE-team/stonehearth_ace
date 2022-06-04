[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform mat4 shadowMats[4];

in vec3 vertPos;
in vec3 normal;
in vec4 color;

out vec4 pos;
out vec3 tsbNormal;
out vec3 albedo;

#ifndef DISABLE_SHADOWS
out vec4 projShadowPos[3];
#endif

void main( void )
{
  pos = calcWorldPos(vec4(vertPos, 1.0));
  vec4 vsPos = calcViewPos(pos);
  tsbNormal = calcWorldVec(normal);
  albedo = color.rgb;

#ifndef DISABLE_SHADOWS
  projShadowPos[0] = shadowMats[0] * pos;
  projShadowPos[1] = shadowMats[1] * pos;
  projShadowPos[2] = shadowMats[2] * pos;
#endif

  gl_Position = viewProjMat * pos;

  // Yuck!  But this saves us an entire vec4, which can kill older cards.
  pos.w = vsPos.z;
}


[[FS]]
#version 410
out vec4 fragColor;
// =================================================================================================

#include "shaders/utilityLib/fragLighting.glsl"

#ifndef DISABLE_SHADOWS
in vec4 projShadowPos[3];
#include "shaders/shadows.shader"
#endif

uniform vec3 lightAmbientColor;

in vec4 pos;
in vec3 albedo;
in vec3 tsbNormal;


void main( void )
{
  // Shadows.
  float shadowTerm = 1.0;

#ifndef DISABLE_SHADOWS
  shadowTerm = getShadowValue(pos.xyz);
#endif

  // Light Color.
  vec3 lightColor = calcSimpleDirectionalLight(normalize(tsbNormal));

  // Mix light and shadow and ambient light.
  lightColor = albedo * (shadowTerm * lightColor + lightAmbientColor);

  fragColor = vec4(lightColor, 1.0);
}