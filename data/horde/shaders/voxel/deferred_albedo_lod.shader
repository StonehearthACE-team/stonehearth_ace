[[FX]]
float4 gridlineColor = { 0.0, 0.0, 0.0, 0.0 };

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

uniform mat4 viewProjMat;

in vec3 vertPos;
in vec3 color;
in vec3 normal;

out float vsDepth;
out vec3 albedo;
out vec3 tsbNormal;
out vec3 worldPosition;
out vec3 gridLineCoords;
out float isAnimated;

void main( void )
{
  vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
  vec4 vsPos = calcViewPos(pos);

  gridLineCoords = pos.xyz + vec3(0.5, 0, 0.5);
  vsDepth = -vsPos.z;
  tsbNormal = calcWorldVec(normal);
  worldPosition = pos.xyz;
  albedo = color;
  isAnimated = checkIsAnimated();
  gl_Position = viewProjMat * pos;
}

[[FS]]
#version 410
out vec4 fragColor;
#include "shaders/utilityLib/psCommon.glsl"
#include "shaders/utilityLib/fragWeather.glsl"

uniform mat4 viewMat;
uniform vec4 lodLevels;
uniform sampler2D fow;
uniform sampler3D gridMap;
uniform vec4 gridlineColor;
uniform float gridActive;

in float vsDepth;
in vec3 albedo;
in vec3 gridLineCoords;
in vec3 tsbNormal;
in vec3 worldPosition;
in float isAnimated;

void main(void)
{
  // First, compute our lod percentage function--this will look like:
  // 0 for the lod level 0, (0, 1) for between the lod levels, and 1 for lod level 1.
  float f = clamp((lodLevels.y - vsDepth) / lodLevels.w, 0.0, 1.0);

  // Next, if we're rendering at lod 1, we actually want to invert this.
  f = abs(lodLevels.x - f);

  // Finally, we actually want to remove the part where we're at lod 1 (since this will already
  // be drawn), so subtract out that piece.
  f = f - step(1.0, f);

  if (f > 0.0) {
     vec3 color = colorizeByWeather(albedo, fow, worldPosition, normalize(tsbNormal), isAnimated);

     // gridlineAlpha is a single float containing the global opacity of gridlines for all
     // nodes.  gridlineColor is the per-material color of the gridline to use.  Only draw
     // them if both are > 0.0.
     float gridline = mix(1.0, texture(gridMap, gridLineCoords).a, gridActive);
     color = mix(gridlineColor.rgb, color, mix(1.0, gridline, gridlineColor.a));

     // TODO: Figure out why this is rendered twice (with an ADD state), which is why we have the half factor.
     fragColor = vec4(0.5 * color, 1.0);
  } else {
     fragColor = vec4(0.0, 0.0, 0.0, 1.0);
  }
}
