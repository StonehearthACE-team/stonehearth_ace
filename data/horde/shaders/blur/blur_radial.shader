[[FX]]

sampler2D depthBuffer = sampler_state
{
  Address = Clamp;
  Filter = None;
};

sampler2D ssaoImage = sampler_state
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
#include "shaders/utilityLib/blur.glsl"

in vec2 texCoords;
uniform sampler2D depthBuffer;
uniform sampler2D ssaoImage;
uniform vec4 frameBufSize;

const int g_BlurRadius = 2;

void main()
{
    float b = 0.0;
    float w_total = 0.0;
    //float center_c = texture(ssaoImage, texCoords).r;
    //float pixelDepth = texture(depthBuffer, texCoords).r;

    vec2 g_InvResolution = frameBufSize.zw;

    b = BlurFunction(texCoords, 0.0, 0.0, w_total, depthBuffer, ssaoImage);
    for (int r = -g_BlurRadius; r <= g_BlurRadius; ++r)
    {
      for (int s = -g_BlurRadius; s <= g_BlurRadius; ++s)
      {
        if (r != 0 && s != 0) {
          float rf = float(r);
          float sf = float(s);
          vec2 uv = texCoords + vec2(rf, sf) * g_InvResolution;
          b += BlurFunction(uv, abs(rf) + abs(sf), 0.0, w_total, depthBuffer, ssaoImage);
        }
      }
    }

    float result = b / w_total;
    fragColor = vec4(vec3(result), 0.0);
}
