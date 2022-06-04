[[FX]]



[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform float currentTime;

in vec3 vertPos;
in vec4 color;

out vec4 outColor;

void main() {
   float m = mod(currentTime * 200.0, 1000.0);
   if (m > 500.0) {
      m = 1000.0 - m;
   }
   outColor = color * (m / 250.0);
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;

in vec4 outColor;

void main() {
   fragColor = outColor.rgba;
}
