[[FX]]


[[VS]]
#version 410
// Cubemitters can take two different paths for rendering (instancing, and the fallback: batching),
// so always use the cubemitter interface to get your data!

#include "shaders/utilityLib/cubemitterCommon.glsl"
#include "shaders/utilityLib/desaturate.glsl"

uniform mat4 viewProjMat;

out vec4 color;

void main(void)
{
  color = globalDesaturateRGBA(cubemitter_getColor());
  gl_Position = viewProjMat * cubemitter_getWorldspacePos();
}

[[FS]]
#version 410
out vec4 fragColor;
in vec4 color;

void main( void )
{
  fragColor = color;
}
