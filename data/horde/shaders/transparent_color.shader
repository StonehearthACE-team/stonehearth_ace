[[FX]]

float4 alpha = { 0, 0, 0, 0.5 };

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;
uniform vec4 alpha;

in vec3 vertPos;
in vec4 color;
in vec3 normal;

out vec4 outColor;
out vec3 tsbNormal;

void main() {
   outColor = vec4(color.rgb, alpha.a);
   tsbNormal = calcWorldVec(normal);
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;
#include "shaders/utilityLib/desaturate.glsl"

in vec4 outColor;

in vec3 tsbNormal;

const vec3 lightDir = vec3(-0.3, -0.5, 0.8);

void main() {
   // We light blueprints with a pretend light at a fixed orientation, so that we give some
   // depth cues to the user, without worrying about where the sun/moon might be.
   float atten = min(abs(dot(tsbNormal, lightDir)) + 0.3, 1.0);
   vec4 theColor = vec4(outColor.rgb * atten, outColor.a);
   fragColor = globalDesaturateRGBA(theColor);
}

