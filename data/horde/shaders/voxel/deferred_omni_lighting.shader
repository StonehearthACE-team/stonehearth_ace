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

uniform mat4 viewProjMat;
uniform mat4 worldMat;
in vec3 vertPos;
out vec4 tCoords;

void main(void)
{
  vec4 clipPos = viewProjMat * worldMat * vec4(vertPos, 1.0);
  tCoords = clipPos;
  gl_Position = clipPos;
}


[[FS]]
#version 410
out vec4 fragColor;

#include "shaders/omni_shadows.shader"
#include "shaders/utilityLib/fragLighting.glsl"
#include "shaders/utilityLib/camera_transforms.glsl"

uniform mat4 camProjMat;
uniform mat4 camViewMatInv;
uniform vec3 camViewerPos;
uniform vec3 lightAmbientColor;
uniform sampler2D normals;
uniform sampler2D depths;

in vec4 tCoords;

void main(void)
{
  vec2 texCoords = ((tCoords.xy / tCoords.w * 0.5) + vec2(0.5));
  vec4 normal = texture(normals, texCoords);
  // Check to see if a valid normal was even written!
  if (normal.w == 0.0) {
  	discard;
  }

  vec4 depthAttribs = texture(depths, texCoords);
  mat4 lProj = camProjMat;
  mat4 lView = camViewMatInv;
  vec3 pos = toWorldSpace(lProj, lView, texCoords, depthAttribs.r);
  float shadowTerm = getOmniShadowValue(lightPos.xyz, pos);

  // Light Color.
  fragColor = globalDesaturateRGBA(calcPhongOmniLight(camViewerPos, pos, normal.xyz, depthAttribs.b, depthAttribs.a) * shadowTerm);
}
