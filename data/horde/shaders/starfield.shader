[[FX]]

float4 brightness;

// Samplers
sampler2D twinkleMap = sampler_state
{
  Texture = "textures/environment/twinkle.png";
  Address = Wrap;
  Filter = None;
};

[[VS]]
#version 410

uniform mat4 worldMat;
uniform mat4 viewProjMat;
uniform vec4 frameBufSize;
uniform float currentTime;
uniform vec4 brightness;

in vec3 vertPos;
in vec2 texCoords0;
in vec2 texCoords1;

out float oBrightness;
out vec2 texCoords;

void main() {
  vec4 clipPos = viewProjMat * worldMat * vec4(vertPos, 1.0);
  clipPos.x += (clipPos.w * 1.5 *  texCoords0.x * frameBufSize.z);
  clipPos.y += (clipPos.w * 1.5 * texCoords0.y * frameBufSize.w);

  texCoords = vertPos.xy + vec2(currentTime, currentTime);
  oBrightness = texCoords1.x * brightness.x;
  gl_Position = clipPos;
}

[[FS]]
#version 410
out vec4 fragColor;

uniform sampler2D twinkleMap;

in float oBrightness;
in vec2 texCoords;

void main() {
  float finalBrightness = oBrightness * (texture(twinkleMap, texCoords).x * 2.0);
  fragColor = vec4(vec3(1.0), finalBrightness);
}
