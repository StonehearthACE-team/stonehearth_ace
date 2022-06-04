[[FX]]

sampler2D lighting = sampler_state
{
  Filter = None;
  Address = Clamp;
};

sampler2D albedo = sampler_state
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

uniform sampler2D lighting;
uniform sampler2D scattering;
uniform sampler2D albedo;
uniform vec3 camViewerPos;
uniform mat4 camProjMat;
uniform mat4 camViewMatInv;

in vec2 texCoords;

void main(void)
{
  vec4 light = texture(lighting, texCoords);
  vec3 albedo = texture(albedo, texCoords).rgb;
  vec3 scatter = texture(scattering, texCoords).rgb;
  float alpha = dot(light, light) > 0 ? 1.0 : 0.0;

  vec3 color = ((albedo * light.rgb) + light.aaa);
  fragColor = vec4(color, alpha);
}
