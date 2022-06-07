[[FX]]

// Samplers
sampler2D image = sampler_state
{
  Address = ClampBorder;
  Filter = Pixely;
};

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 projectorMat;
uniform mat4 viewProjMat;

in vec3 vertPos;

out vec4 pos;
out vec2 texCoords;

void main( void )
{
  pos = calcWorldPos(vec4(vertPos, 1.0));
  texCoords = (projectorMat * pos).xz;

  gl_Position = viewProjMat * pos;
}


[[FS]]
#version 410
out vec4 fragColor;
uniform sampler2D image;

in vec2 texCoords;

void main() {
  fragColor = texture(image, texCoords);
}
