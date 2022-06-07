
#include "shaders/utilityLib/desaturate.glsl"

uniform samplerCube shadowMap;
uniform float shadowFactor;

float getOmniShadowValue(const vec3 lightPos, const vec3 worldSpace_fragmentPos)
{
  float shadowTerm = 1.0;

#ifndef DISABLE_SHADOWS
  if (global_desaturate_multiplier == 0.0) {
     vec3 lightDir = worldSpace_fragmentPos - lightPos;
     float lightDist = length(lightDir);

     // This really seems to suggest something very slightly, subtly, horribly wrong....
     lightDir.xy *= -1.0;

     float dist = texture(shadowMap, lightDir).r;
     shadowTerm = (dist >= lightDist - 0.1 ) ? 1.0 : 0.0;
  }
#endif

  return mix(1.0, shadowTerm, shadowFactor);
}

