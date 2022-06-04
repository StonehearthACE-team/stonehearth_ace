[[FX]]

float4 alpha = { 0, 0, 0, 0.5 };
float4 playerColor = { 0, 0, 0, 1.0 };

float4 cameraAxis = { 0, 0, 1.0, 0 };

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform vec3 camViewerPos;
uniform vec4 alpha;
uniform vec4 playerColor;
uniform vec4 cameraAxis;

in vec3 vertPos;
in vec4 color;
in vec3 normal;

out vec4 outColor;
out vec3 aligned;
out vec3 camAxis;

void main() {
   outColor = vec4(playerColor.rgb, alpha.a);
   vec4 worldPos = calcWorldPos(vec4(vertPos, 1.0));
   gl_Position = viewProjMat * worldPos;
   aligned = normalize(calcWorldVec(normal));
   camAxis = normalize(worldPos.xyz - camViewerPos);
}

[[FS]]
#version 410
out vec4 fragColor;
in vec4 outColor;
in vec3 aligned;
in vec3 camAxis;

void main() {
   // more transparent when the normal is aligned with our view
   float alphaMagnitude = abs(dot(aligned, camAxis));
   float sinMag = min(smoothstep(0.0, 0.6, alphaMagnitude), 1.0 - smoothstep(0.0, 1.0, alphaMagnitude)); // outer edge, inner edge

   // add shading to the sphere
   float darkness = min(1.0, (1.0 - aligned.y) / 2.0);
   fragColor = vec4(outColor.rgb * darkness, outColor.a * sinMag);
}
