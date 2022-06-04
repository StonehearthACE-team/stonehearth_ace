[[FX]]

float4 alpha = { 0, 0, 0, 0.5 };
float use_custom_alpha;  // Really bool


[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform vec4 alpha;
uniform float use_custom_alpha;

in vec3 vertPos;
in vec4 color;

out vec4 outColor;


void main() {
   outColor = vec4(color.rgb, mix(color.a, alpha.a, use_custom_alpha));
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;
in vec4 outColor;

void main() {
   fragColor = outColor;
}

