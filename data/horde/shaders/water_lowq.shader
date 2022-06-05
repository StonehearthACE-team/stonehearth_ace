[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform float lowq_waterAmbientLightScale;

in vec3 vertPos;
in vec4 color;

out vec4 outColor;

void main() {
   outColor = vec4(color.rgb * min(1.0, lowq_waterAmbientLightScale), color.a);
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;

in vec4 outColor;

void main() {
   fragColor = outColor;
}
