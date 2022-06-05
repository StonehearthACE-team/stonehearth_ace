[[FX]]

sampler2D normals = sampler_state
{
  Filter = None;
  Address = Clamp;
};

sampler2D depths = sampler_state
{
  Filter = None;
  Address = Clamp;
};

[[VS]]
#version 410

uniform mat4 projMat;
in vec3 vertPos;
out vec2 texCoords;

void main(void)
{
  texCoords = vertPos.xy;
  gl_Position = projMat * vec4(vertPos, 1.0);
}


[[FS]]
#version 410
out vec4 fragColor;

#include "shaders/utilityLib/camera_transforms.glsl"
#include "shaders/utilityLib/fragLighting.glsl"
#include "shaders/utilityLib/desaturate.glsl"

#ifndef DISABLE_SHADOWS
in vec4 projShadowPos[3];
#include "shaders/shadows.shader"
#endif

uniform vec3 lightAmbientColor;
uniform sampler2D normals;
uniform sampler2D depths;
uniform vec3 camViewerPos;
uniform mat4 camProjMat;
uniform mat4 camViewMatInv;

in vec2 texCoords;

void main(void)
{
  vec4 normal = texture(normals, texCoords);

  // Check to see if a valid normal was even written!
  if (normal.w == 0.0) {
  	discard;
  }

  float shadowTerm = 1.0;
  vec4 depthInfo = texture(depths, texCoords);

  mat4 lProj = camProjMat;
  mat4 lView = camViewMatInv;
  vec3 pos = toWorldSpace(lProj, lView, texCoords, depthInfo.r);

  #ifndef DISABLE_SHADOWS
    shadowTerm = getShadowValue_deferred(pos) * (1.0 - global_desaturate_multiplier);
  #endif

  vec4 lightColor = calcPhongDirectionalLight(camViewerPos, pos, normal.xyz, depthInfo.b, depthInfo.a) * shadowTerm;
  fragColor = vec4(globalDesaturate(lightColor.rgb + ambientShade * lightAmbientColor), lightColor.a);
}
