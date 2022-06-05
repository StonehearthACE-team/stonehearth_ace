[[FX]]
float4 alpha = {0, 0, 0, 0.5};

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform    mat4    viewProjMat;
uniform    vec4    alpha;
in vec3    vertPos;
in vec3    color;
out vec4    vs_color;

void main() {
   vs_color = vec4(color, alpha.a);
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;
in vec4 vs_color;
void main() {
  fragColor = vs_color;
}
