[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;

in vec3 vertPos;
in vec3 normal;

out vec4 vsPos;
out vec3 tsbNormal;
out float worldScale;

void main( void )
{
  vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
  tsbNormal = calcWorldVec(normal);
  worldScale = getWorldScale();
  gl_Position = viewProjMat * pos;
}

[[FS]]
#version 410
layout(location = 0) out vec4 fragData_0;
layout(location = 1) out vec4 fragData_1;
#include "shaders/utilityLib/psCommon.glsl"

uniform mat4 viewMat;

in vec3 tsbNormal;
in float worldScale;

void main(void)
{
  fragData_0.r = toLinearDepth(gl_FragCoord.z);
  fragData_0.g = worldScale;
  fragData_1 = viewMat * vec4(normalize(tsbNormal), 0.0);
}
