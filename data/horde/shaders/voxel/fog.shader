[[FX]]

sampler2D skySampler = sampler_state
{
  Address = Clamp;
  Filter = Trilinear;
};


[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;

in vec3 vertPos;
out vec4 vsPos;

void main( void )
{
  vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
  vsPos = calcViewPos(pos);

  gl_Position = viewProjMat * pos;
}


[[FS]]
#version 410
out vec4 fragColor;
#include "shaders/utilityLib/fog.glsl"

uniform sampler2D skySampler;
uniform vec4 frameBufSize;
uniform float farPlane;

in vec4 vsPos;

void main( void )
{
  float fogFac = calcFogFac(vsPos.z, farPlane);
  vec3 fogColor = texture(skySampler, gl_FragCoord.xy * frameBufSize.zw).rgb;

  fragColor = vec4(fogColor, fogFac);
}
