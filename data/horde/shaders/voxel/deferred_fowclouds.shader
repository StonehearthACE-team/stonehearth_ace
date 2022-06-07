[[FX]]

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

sampler2D depths = sampler_state
{
  Filter = None;
  Address = Clamp;
};

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 projMat;
in vec3 vertPos;
out vec2 texCoords;

void main( void )
{
  texCoords = vertPos.xy;
  gl_Position = projMat * vec4(vertPos, 1.0);
}


[[FS]]
#version 410
out vec4 fragColor;
// =================================================================================================

#include "shaders/utilityLib/fragLighting.glsl"
#include "shaders/utilityLib/camera_transforms.glsl"

uniform sampler2D cloudMap;
uniform sampler2D fowRT;
uniform sampler2D depths;
uniform float currentTime;
uniform mat4 camProjMat;
uniform mat4 camViewMatInv;
uniform mat4 fowViewMat;

in vec2 texCoords;

uniform float global_desaturate_multiplier;
uniform float cloud_speed = 1;
uniform float cloud_opacity = 1;

void main(void)
{
  mat4 pMat = camProjMat;
  mat4 cVIMat = camViewMatInv;
  vec3 pos = toWorldSpace(pMat, cVIMat, texCoords, texture(depths, texCoords).r);
  vec4 projFowPos = fowViewMat * vec4(pos, 1.0);

  // Mix in cloud color.
  float cloudSpeed = currentTime * 0.0125 * cloud_speed;
  vec2 fragCoord = pos.xz * 0.3;
  vec3 cloudColor = texture(cloudMap, fragCoord.xy / 128.0 + cloudSpeed).rgb;
  cloudColor = texture(cloudMap, fragCoord.yx / 192.0 + (cloudSpeed / 10.0)).rgb;
  cloudColor = mix(vec3(1.0, 1.0, 1.0), cloudColor, cloud_opacity);

  // Mix in fog of war.
  // Make sure we don't sample exactly on pixel borders, as otherwise rounding errors will
  // cause texels on vertical surfaces aligned to the texture to take values from different FOW pixels.
  // Mirrored in dir_lighting_f.shader
  // See: https://jira.riotgames.com/browse/STNHRTQA-426
  vec3 fowValue = vec3(texture(fowRT, projFowPos.xy + 0.0001).a);
  cloudColor = max(vec3(global_desaturate_multiplier), cloudColor);

  fragColor = vec4(cloudColor * fowValue, 1.0);
}