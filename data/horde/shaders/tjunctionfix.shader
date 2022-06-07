[[FX]]

sampler2D selections = sampler_state
{
  Address = Clamp;
  Filter = None;
};

[[VS]]
#version 410
#include "shaders/fsquad_vs.glsl"


[[FS]]
#version 410
out vec4 fragColor;

uniform sampler2D selections;
uniform vec4 frameBufSize;

in vec2 texCoords;

void main(void)
{
  vec2 offset = frameBufSize.zw;
  vec4 sampleColor = texture(selections, texCoords);

  if (sampleColor.a > 0.0) {
	fragColor = sampleColor;
  	return;
  }

  vec4 sampleLeft = texture(selections, texCoords + vec2(-offset.x, 0.0));
  vec4 sampleRight = texture(selections, texCoords + vec2(offset.x, 0.0));

  if (sampleLeft.a > 0.0 && sampleRight.a > 0.0) {
  	fragColor = sampleLeft;
  	return;
  }

  fragColor = sampleColor;
  return;
}
