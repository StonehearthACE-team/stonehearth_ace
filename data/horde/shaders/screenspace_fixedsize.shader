// This is a screen-space shader that renders hud elements in the world, but with a fixed screen-space
// size.  That is, the hud element will not grow/shrink as the user changes their position relative to
// the object to which the element is attached.
[[FX]]

sampler2D albedoMap = sampler_state
{
  Address = Clamp;
  Filter = Pixely;
};

sampler2D foregroundMap = sampler_state
{
  Address = Clamp;
  Filter = Pixely;
};

float4 playerColor;

[[VS]]
#version 410
uniform vec2 viewPortSize;
uniform mat4 viewProjMat;
uniform mat4 worldMat;

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
  vec2 scale = origin.w * vec2(2.0 / viewPortSize.x, 2.0 / viewPortSize.y);
  vec4 screenPos = vec4(vertPos.xy + offset, 0, 0);

  gl_Position = origin + screenPos * scale.xyxy;
}


[[FS]]
#version 410
out vec4 fragColor;

uniform sampler2D albedoMap;
uniform sampler2D foregroundMap;
uniform vec4 playerColor;

in vec4 oColor;
in vec2 texCoords;

void main() {
  vec4 foreground = texture(foregroundMap, texCoords);
  vec4 background = playerColor * texture(albedoMap, texCoords);

  vec4 composed = vec4(mix(background.rgb, foreground.rgb, foreground.a), background.a);

  fragColor = oColor * composed;
  gl_FragDepth = fragColor.a > 0.5 ? gl_FragCoord.z : 1.0;
}
