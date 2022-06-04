[[FX]]
float4 gridlineColor = { 0.0, 0.0, 0.0, 0.0 };

float4 glossy = { 0.0, 0.0, 0.0, 0.0 };

// Samplers
sampler2D fow = sampler_state
{
   Address = Clamp;
   Filter = Pixely;
};

sampler3D gridMap = sampler_state
{
   Texture = "textures/common/gridMap.dds";
   Filter = Trilinear;
};

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"
#include "shaders/utilityLib/desaturate.glsl"
#include "shaders/utilityLib/atmosphere.glsl"

uniform mat4 viewProjMat;

// Atmosphere uniforms
uniform vec4 celestialLightPos;
uniform vec4 heightFogParams;
uniform vec4 heightFogParams2;
uniform vec4 scatteringParams;
uniform vec3 camViewerPos;

in vec3 vertPos;
in vec3 normal;
in vec3 color;

out float vsDepth;
out vec3 albedo;
out vec3 tsbNormal;
out vec3 worldPosition;
out float worldScale;
out vec3 gridLineCoords;
out float isAnimated;

// Atmosphere out
out vec3 scatteringOutColor;
out vec3 scatteringOutAttenuation;
out float fogOut;

void main( void )
{
  vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
  vec4 vsPos = calcViewPos(pos);

  scattering(pos, vsPos, celestialLightPos, camViewerPos, scatteringParams, scatteringOutColor, scatteringOutAttenuation);
  fogOut = heightFog(pos, heightFogParams, heightFogParams2);

  gridLineCoords = pos.xyz + vec3(0.5, 0, 0.5);
  vsDepth = -vsPos.z;
  albedo = globalDesaturate(color) * 0.5;
  tsbNormal = calcWorldVec(normal);
  worldPosition = pos.xyz;
  worldScale = getWorldScale();
  isAnimated = checkIsAnimated();
  gl_Position = viewProjMat * pos;
}

[[FS]]
#version 410
layout(location = 0) out vec4 fragData_0;
layout(location = 1) out vec4 fragData_1;
layout(location = 2) out vec4 fragData_2;
layout(location = 3) out vec4 fragData_3;
#include "shaders/utilityLib/psCommon.glsl"
#include "shaders/utilityLib/fragWeather.glsl"

uniform mat4 viewMat;
uniform vec4 lodLevels;
uniform sampler2D fow;
uniform sampler3D gridMap;
uniform vec4 gridlineColor;
uniform vec4 glossy;
uniform float gridActive;

in float vsDepth;
in vec3 albedo;
in vec3 tsbNormal;
in vec3 worldPosition;
in float worldScale;
in vec3 gridLineCoords;
in float isAnimated;

// Atmosphere out
in vec3 scatteringOutColor;
in vec3 scatteringOutAttenuation;
in float fogOut;

void main(void)
{
  fragData_0.r = vsDepth; //toLinearDepth(gl_FragCoord.z);
  fragData_0.g = worldScale;
  fragData_0.b = glossy.z;
  fragData_0.a = glossy.a;

  fragData_1 = vec4(normalize(tsbNormal), 1.0);

  float f = 1.0;
  if (lodLevels.x == 0.0) {
    if (vsDepth > lodLevels.z) {
      f = 0.0;
    }
  } else {
    if (vsDepth < lodLevels.y) {
      // By the time we see this pixel in the second LOD level, it has already been painted by the first LOD level,
      // just discard, and don't bother contributing.  Maybe we should just stencil mask, since putting discard
      // in a shader can have perf implications?
      discard;
    }
  }

  if (f > 0.0) {
     vec3 color = colorizeByWeather(albedo, fow, worldPosition, normalize(tsbNormal), isAnimated);

     // gridlineAlpha is a single float containing the global opacity of gridlines for all
     // nodes.  gridlineColor is the per-material color of the gridline to use.  Only draw
     // them if both are > 0.0.
     float gridline = mix(1.0, texture(gridMap, gridLineCoords).a, gridActive);
     color = mix(gridlineColor.rgb, color, mix(1.0, gridline, gridlineColor.a));

     fragData_2 = vec4(color, 1.0);
  } else {
     fragData_2 = vec4(0.0, 0.0, 0.0, 1.0);
  }

  // Atmosphere
  fragData_3 = vec4(0.0325 * scatteringOutAttenuation + scatteringOutColor, fogOut);
}
