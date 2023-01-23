[[FX]]

// Samplers
sampler2D albedoMap  = sampler_state
{
	Filter = Pixely;
	Address = Clamp;
};

sampler2D backgroundMap = sampler_state
{
  Address = Clamp;
  Filter = Pixely;
};


[[VS]]
#version 410
uniform vec2 viewPortSize;
uniform mat4 viewProjMat;
uniform mat4 worldMat;
uniform sampler2D albedoMap;

in vec4 vertPos;
in vec2 texCoords0;
in vec4 color;

out vec4 oColor;
out vec2 texCoords;

void main() {
  texCoords = texCoords0;
  oColor = color;

  vec4 origin = viewProjMat * worldMat * vec4(0.0, 0.0, 0.0, 1.0);
  vec2 offset = vertPos.zw;
  ivec2 texSize = textureSize(albedoMap, 0);
  vec2 scale = origin.w * vec2(0.03 * float(texSize.x) / viewPortSize.x, 0.03 * float(texSize.y) / viewPortSize.y);
  vec4 screenPos = vec4(vertPos.xy + offset, 0, 0);

  gl_Position = origin + screenPos * scale.xyxy;
}


[[FS]]
#version 410
out vec4 fragColor;
uniform sampler2D albedoMap;

in vec4 oColor;
in vec2 texCoords;

void main() {
  vec4 foreground = texture2D(albedoMap, texCoords);
  fragColor = foreground * oColor;
  //gl_FragDepth = fragColor.a > 0.5 ? gl_FragCoord.z : 1.0;
}
