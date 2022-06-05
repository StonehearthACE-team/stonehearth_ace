[[FX]]

float4 gridlineColor = { 0.0, 0.0, 0.0, 0.0 };
float cloud_speed = 1.0;

// Samplers
sampler3D gridMap = sampler_state
{
   Texture = "textures/common/gridMap.dds";
   Filter = Trilinear;
};

sampler2D cloudMap = sampler_state
{
  Texture = "textures/environment/cloudmap.png";
  Address = Wrap;
  Filter = Pixely;
};

sampler2D fowRT = sampler_state
{
  Filter = None;
  Address = Clamp;
};

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform mat4 shadowMats[4];
uniform mat4 fowViewMat;

in vec3 vertPos;
in vec3 normal;
in vec4 color;

out vec4 pos;
out vec3 tsbNormal;
out vec3 albedo;
out float isAnimated;

#ifndef DISABLE_SHADOWS
out vec4 projShadowPos[3];
#endif

out vec4 projFowPos;
out vec3 gridLineCoords;

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

  projFowPos = fowViewMat * pos;

  gridLineCoords = pos.xyz + vec3(0.5, 0, 0.5);

  isAnimated = checkIsAnimated();

  gl_Position = viewProjMat * pos;

  // Yuck!  But this saves us an entire vec4, which can kill older cards.
  pos.w = vsPos.z;
}


[[FS]]
#version 410
out vec4 fragColor;
// =================================================================================================

#include "shaders/utilityLib/fragLighting.glsl"
#include "shaders/utilityLib/desaturate.glsl"
#include "shaders/utilityLib/fragWeather.glsl"

#ifndef DISABLE_SHADOWS
in vec4 projShadowPos[3];
#include "shaders/shadows.shader"
#endif

uniform sampler3D gridMap;
uniform sampler2D cloudMap;
uniform sampler2D fowRT;
uniform vec4 gridlineColor;
uniform vec4 lodLevels;
uniform vec3 lightAmbientColor;
uniform float currentTime;
uniform float gridActive;

in vec4 pos;
in vec4 projFowPos;
in vec3 tsbNormal;
in vec3 albedo;
in vec3 gridLineCoords;
in float isAnimated;

uniform float cloud_speed;
uniform float cloud_opacity;

void main( void )
{
  // Shadows.
  float shadowTerm = 1.0;

#ifndef DISABLE_SHADOWS
  shadowTerm = getShadowValue(pos.xyz);
#endif

  vec3 normal = normalize(tsbNormal);

  vec3 color = colorizeByWeather(albedo, fowRT, pos.xyz, normal, isAnimated);

  // Light Color.
  vec3 lightColor = calcSimpleDirectionalLight(normal);

  // Mix light and shadow and ambient light.
  lightColor = color * (max(shadowTerm, global_desaturate_multiplier) * lightColor + lightAmbientColor);

  // Mix in cloud color.
  float cloudSpeed = currentTime * 0.0125 * cloud_speed;
  vec2 fragCoord = pos.xz * 0.3;
  vec3 cloudColor = texture(cloudMap, fragCoord.xy / 128.0 + cloudSpeed).xyz;
  cloudColor = max(cloudColor * texture(cloudMap, fragCoord.yx / 192.0 + (cloudSpeed / 10.0)).xyz, global_desaturate_multiplier);
  cloudColor = mix(vec3(1.0, 1.0, 1.0), cloudColor, cloud_opacity);
  lightColor *= cloudColor;

  // Mix in fog of war.
  // Make sure we don't sample exactly on pixel borders, as otherwise rounding errors will
  // cause texels on vertical surfaces aligned to the texture to take values from different FOW pixels.
  // Mirrored in deferred_fowclouds.shader
  // See: https://jira.riotgames.com/browse/STNHRTQA-426
  float fowValue = texture(fowRT, projFowPos.xy + 0.0001).a;
  lightColor *= fowValue;


  // Do LOD blending.  Note that pos.w is view-space 'z' coordinate (see VS.)
  // First, compute our lod percentage function--this will look like:
  // 0 for the lod level 0, (0, 1) for between the lod levels, and 1 for lod level 1.
  float f = clamp((lodLevels.y + pos.w) / lodLevels.w, 0.0, 1.0);

  // Next, if we're rendering at lod 1, we actually want to invert this.
  f = abs(lodLevels.x - f);

  lightColor *= f;

  // gridlineAlpha is a single float containing the global opacity of gridlines for all
  // nodes.  gridlineColor is the per-material color of the gridline to use.  Only draw
  // them if both are > 0.0.
  float gridline = mix(1.0, texture(gridMap, gridLineCoords).a, gridActive);
  lightColor = mix(gridlineColor.rgb, lightColor, mix(1.0, gridline, gridlineColor.a));

  fragColor = vec4(globalDesaturate(lightColor), 1.0);
}