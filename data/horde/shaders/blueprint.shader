[[FX]]

float4 gridlineColor = { 0.0, 0.0, 0.0, 1.0 };
float blueprintAlpha = 0.25;

sampler3D gridMap = sampler_state
{
   Texture = "textures/common/gridMap.dds";
   Filter = Trilinear;
};

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"

uniform mat4 viewProjMat;

in vec3 vertPos;
in vec3 color;
in vec3 normal;

out vec3 outColor;
out vec3 tsbNormal;
out vec3 worldPos;

void main() {
   outColor = color;
   tsbNormal = calcWorldVec(normal);
   worldPos = calcWorldPos(vec4(vertPos, 1.0)).xyz;
   gl_Position = viewProjMat * calcWorldPos(vec4(vertPos, 1.0));
}

[[FS]]
#version 410
out vec4 fragColor;
uniform sampler3D gridMap;
uniform vec4 gridlineColor;
uniform float blueprintAlpha;

in vec3 outColor;
in vec3 tsbNormal;
in vec3 worldPos;

const vec3 lightDir = vec3(-0.3, -0.5, 0.8);

void main() {
   // We light blueprints with a pretend light at a fixed orientation, so that we give some
   // depth cues to the user, without worrying about where the sun/moon might be.
   float atten = min(abs(dot(tsbNormal, lightDir)) + 0.3, 1.0);
   vec4 theColor = vec4(outColor * atten, 1.0);
   vec4 gridline = texture(gridMap, worldPos + vec3(0.5, 0, 0.5));
   gridline = vec4(1.0, 1.0, 1.0, 1.0) - gridline;
   float blendAlpha = gridline.a * gridlineColor.a;
   fragColor.rgb = theColor.rgb * (1.0 - blendAlpha) + (gridlineColor.rgb * blendAlpha);
   fragColor.a = blueprintAlpha;
}
