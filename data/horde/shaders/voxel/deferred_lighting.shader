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

uniform mat4 projMat;
attribute vec3 vertPos;
varying vec2 texCoords;
        
void main(void)
{
  texCoords = vertPos.xy; 
  gl_Position = projMat * vec4(vertPos, 1.0);
}


[[FS]]
#version 120
#include "/stonehearth/data/horde/shaders/utilityLib/camera_transforms.glsl"
#include "/stonehearth_ace/data/horde/shaders/utilityLib/fragLighting.glsl" 
#include "/stonehearth/data/horde/shaders/utilityLib/desaturate.glsl"

#ifndef DISABLE_SHADOWS
varying vec4 projShadowPos[3];
#include "shaders/shadows.shader"
#endif

uniform vec3 lightAmbientColor;
uniform sampler2D normals;
uniform sampler2D depths;
uniform vec3 camViewerPos;
uniform mat4 camProjMat;
uniform mat4 camViewMatInv;

varying vec2 texCoords;

void main(void)
{
  vec4 normal = texture2D(normals, texCoords);

  // Check to see if a valid normal was even written!
  if (normal.w == 0.0) {
  	discard;
  }

  float shadowTerm = 1.0;
  vec4 depthInfo = texture2D(depths, texCoords);

  mat4 lProj = camProjMat;
  mat4 lView = camViewMatInv;
  vec3 pos = toWorldSpace(lProj, lView, texCoords, depthInfo.r);

  #ifndef DISABLE_SHADOWS
    shadowTerm = getShadowValue_deferred(pos) * (1.0 - global_desaturate_multiplier);
  #endif

  vec4 lightColor = calcPhongDirectionalLight(camViewerPos, pos, normal.xyz, depthInfo.b, depthInfo.a) * shadowTerm;
  // Added by ACE, courtesy of Agon
  float ambientShade = calcDirectionalAmbientShade(normal.xyz);
  gl_FragColor = vec4(globalDesaturate(lightColor.rgb + ambientShade * lightAmbientColor), lightColor.a);
}