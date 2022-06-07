[[FX]]

sampler2D randomVectorLookup = sampler_state
{
  Address = Wrap;
  Filter = None;
};

sampler2D sampleVectorLookup = sampler_state
{
  Address = Wrap;
  Filter = None;
};

sampler2D normalBuffer = sampler_state
{
  Address = Clamp;
  Filter = None;
};

sampler2D depthBuffer = sampler_state
{
  Address = Clamp;
  Filter = None;
};

[[VS]]
#version 410
#include "shaders/fsquad_vs.glsl"


[[FS]]
#version 410
#include "shaders/utilityLib/camera_transforms.glsl"
#include "shaders/utilityLib/vertCommon_400.glsl"

#define LOG_MAX_OFFSET 3
#define MAX_MIP_LEVEL 5
#define NUM_SAMPLES 8

uniform sampler2D randomVectorLookup;
uniform sampler2D sampleVectorLookup;
uniform sampler2D normalBuffer;
uniform sampler2D depthBuffer;
uniform vec4 frameBufSize;
uniform mat4 camProjMat;
uniform mat4 camViewMat;

in vec2 texCoords;

out vec4 fragColor;


float getSampleDepth(const vec2 texCoords/*, const float screenSpaceDistance*/) {
  // To be used when I get mipmaps working correctly.
  //ivec2 pixelCoords = ivec2(floor(texCoords * frameBufSize.xy));
  //int mipLevel = 0;//clamp(int(floor(log2(screenSpaceDistance) - LOG_MAX_OFFSET)), 0, MAX_MIP_LEVEL);
  //return texelFetch(depthBuffer, pixelCoords >> mipLevel, mipLevel).ra;

  return texture(depthBuffer, texCoords).r;
}

vec3 getRandomVec(const vec2 texCoords)
{
  vec2 noiseScale = frameBufSize.xy / 4.0;
  return texture(randomVectorLookup, texCoords * noiseScale).xyz;
}


void main()
{
  float radius = 0.5;
  const float intensity = 0.5;

  vec4 attribs = texture(depthBuffer, texCoords);
  mat4 camProj = camProjMat;
  vec3 origin = toCameraSpace(camProj, texCoords, attribs.r);
  radius *= attribs.g;
  vec3 rvec = getRandomVec(texCoords);
  vec3 normal = (camViewMat * vec4(-texture(normalBuffer, texCoords).xyz, 0.0)).xyz;

  vec3 tangent = normalize(rvec - (normal * dot(rvec, normal)));
  vec3 bitangent = cross(normal, tangent);
  mat3 tbn = mat3(tangent, bitangent, normal);

  float occlusion = 0.0;
  for (int i = 0; i < NUM_SAMPLES; i++) {
    // get sample position:
    vec3 cameraSpaceSample = tbn * texture(sampleVectorLookup, vec2(0.0, float(i) / 16.0)).xyz;
    vec3 ssaoSample = (cameraSpaceSample * radius) + origin;

    // project sample position:
    vec4 offset = camProjMat * vec4(ssaoSample, 1.0);
    offset.xy /= offset.w;
    offset.xy = (offset.xy * 0.5) + 0.5;

    // get sample location.
    float sampledDepth = getSampleDepth(offset.xy); //, length((offset.xy - texCoords) * frameBufSize.xy));

    float sampleOcclusion;
    // Range check:
    float rangeCheck = 1.0 - step(radius, abs(origin.z - sampledDepth));
    //float rangeCheck = abs(origin.z - sampledDepth) < radius ? 1.0 : 0.0;

    // Old and busted (and faster :P)
    //occlusion += sampledDepth < ssaoSample.z ? 1.0 * rangeCheck : 0.0;
    occlusion += rangeCheck * (1.0 - step(ssaoSample.z, sampledDepth));

    // New hotness:
    //sampleOcclusion = ((sampledDepths.x < ssaoSample.z) && (sampledDepths.y >= ssaoSample.z)) ? 1.0 : 0.0;
  }

  occlusion /= NUM_SAMPLES;
  occlusion *= intensity;

  fragColor = vec4(vec3(occlusion), 0.0);
}
