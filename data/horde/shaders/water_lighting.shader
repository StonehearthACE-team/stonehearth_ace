[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform vec3 lightAmbientColor;
uniform vec3 lightColor;

in vec3 vertPos;
in vec4 color;
in vec3 normal;

out vec4 outColor;
out vec3 tsbNormal;

void main() {
   outColor = color;
   tsbNormal = -calcWorldVec(normal);
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;

uniform vec4 lightDir;
uniform vec3 lightAmbientColor;
uniform vec3 lightColor;

in vec4 outColor;
in vec3 tsbNormal;

void main() {
   float lightIntensity = length(lightAmbientColor);
   // Add a strong ambient component so that the backside of a water volume doesn't get too dark
   float intensity = lightIntensity * ((max(dot(tsbNormal, lightDir.xyz), 0.0) * 0.5 + 0.5));
   fragColor = vec4(outColor.rgb * intensity, 1.0);
}
