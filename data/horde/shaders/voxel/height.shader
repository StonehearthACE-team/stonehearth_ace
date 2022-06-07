[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;

in vec3 vertPos;

out vec4 pos;

void main( void )
{
   pos = calcWorldPos(vec4(vertPos, 1.0));
   gl_Position = viewProjMat * pos;
}

[[FS]]
#version 410
out vec4 fragColor;
in vec4 pos;

void main(void)
{
   float height = pos.y / 256.0;
   fragColor = vec4(0.0, height, 0.0, 0.0);
}
