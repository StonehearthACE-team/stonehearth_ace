[[FX]]

float4 widgetColor = { 0, 0, 0, 1 };

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform vec4 widgetColor;

in vec3 vertPos;
in vec4 color;
in vec3 normal;

out vec4 outColor;
out vec3 outNormal;

void main() {
   outColor = widgetColor;
   outNormal = normal;
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;

in vec4 outColor;
in vec3 outNormal;

void main() {
   vec3 absN = abs(normalize(outNormal));

   float f = clamp(dot(absN, vec3(0.6)), 0.0, 1.0);

   fragColor = vec4(outColor.rgb * f, outColor.a);
}
