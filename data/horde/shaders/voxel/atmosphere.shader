[[FX]]

[[VS]]
#version 410
#include "shaders/utilityLib/vertCommon.glsl"
#include "shaders/utilityLib/color_transforms.glsl"

uniform mat4 viewProjMat;
uniform vec3 camViewerPos;
uniform vec4 lightPos;
uniform vec4 lightDir;
uniform vec3 lightColor;
uniform vec3 lightAmbientColor;
uniform float currentTime;

uniform vec4 heightFogParams;
uniform vec4 heightFogParams2;
uniform vec4 heightFogColorMult;
uniform vec4 scatteringParams;

in vec3 vertPos;
in vec3 normal;
in vec3 color;

out vec3 col0;
out vec3 col1;
out vec4 fogOutColor;
out vec4 worldPosition;

const int nSamples = 10;
const float fSamples = 10.0;
const float fScaleDepth = 0.25;
const float worldRadius = 6000.0;
const vec3 haze = vec3(0.5, 0.0, 0.5);

float scale(float fCos)
{
   float x = 1.0 - fCos;
   return fScaleDepth * exp(-0.00287 + x*(0.459 + x*(3.83 + x*(-6.80 + x*5.25))));
}

void main(void)
{
   vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
   vec4 vsPos = calcViewPos(pos);
   gl_Position = viewProjMat * pos;
   worldPosition = pos;

   // Scattering
   vec3 bsoffset = vec3(0, worldRadius, 0);
   vec3 wavelength = vec3(0.650, 0.570, 0.475);
   vec3 v3InvWavelength = 1.0 / pow(wavelength, vec3(4.0));
   vec3 v3CameraPos = (1.0 * camViewerPos) + bsoffset;
   vec3 v3LightPos = lightPos.xyz;
   float fCameraHeight = v3CameraPos.y;
   float fCameraHeight2 = fCameraHeight * fCameraHeight;
   float fOuterRadius = worldRadius + 500.0;
   float fOuterRadius2 = fOuterRadius * fOuterRadius;
   float fInnerRadius = worldRadius;
   float fInnerRadius2 = fInnerRadius * fInnerRadius;
   float ESun = scatteringParams.w; // Sun brightness.
   float Kr = 0.00045; // Rayleigh Scattering constant.
   float Km = 0.0001; // Mie Scattering constant.
   float fKrESun = Kr * ESun;
   float fKmESun = Km * ESun;
   float fKr4PI = Kr * 4.0 * 3.14159;
   float fKm4PI = Km * 4.0 * 3.14159;
   float fScale = 1.0 / (fOuterRadius - fInnerRadius);
   float fScaleOverScaleDepth = fScale / fScaleDepth;

   // Get the ray from the camera to the vertex, and its length (which is the far point of the ray passing through the atmosphere)
   vec3 v3Pos = (1.0 * pos.xyz) + bsoffset;
   vec3 v3Ray = v3Pos - v3CameraPos;
   float fFar = length(v3Ray);
   v3Ray /= fFar;

   // Calculate the ray's starting position, then calculate its scattering offset
   vec3 v3Start = v3CameraPos;
   float fDepth = exp((fInnerRadius - fCameraHeight) / fScaleDepth);
   float fCameraAngle = dot(-v3Ray, v3Pos) / length(v3Pos);
   float fLightAngle = dot(v3LightPos, v3Pos) / length(v3Pos);
   float fCameraScale = scale(fCameraAngle);
   float fLightScale = scale(fLightAngle);
   float fCameraOffset = fDepth*fCameraScale;
   float fTemp = (fLightScale + fCameraScale);

   // Initialize the scattering loop variables
   float fSampleLength = fFar / fSamples;
   float fScaledLength = fSampleLength * fScale;
   vec3 v3SampleRay = v3Ray * fSampleLength;
   vec3 v3SamplePoint = v3Start + v3SampleRay * 0.5;

   // Now loop through the sample rays
   vec3 v3FrontColor = vec3(0.0);
   vec3 v3Attenuate = vec3(0.0);
   for(int i=0; i<nSamples; i++)
   {
      float fHeight = v3SamplePoint.y;
      float fDepth = exp(fScaleOverScaleDepth * (fInnerRadius - fHeight));
      float fScatter = fDepth*fTemp - fCameraOffset;
      v3Attenuate = exp(-fScatter * (v3InvWavelength * fKr4PI + fKm4PI));
      v3FrontColor += v3Attenuate * (fDepth * fScaledLength);
      v3SamplePoint += v3SampleRay;
   }

   col0 = (v3FrontColor) * (v3InvWavelength * fKrESun + fKmESun);

   // Transform output
   float hueShiftAmount = scatteringParams.x;
   float saturationFactor = scatteringParams.y;
   float valueFactor = scatteringParams.z;

   col0 = toHSV(col0);
   col0.x = mod(col0.x + hueShiftAmount, 1.0);
   col0.y *= saturationFactor;
   col0.z *= valueFactor;
   col0 = toRGB(col0);

   // Calculate the attenuation factor for the ground
   col1 = v3Attenuate;

   // Height Fog
   float fogHeight = heightFogParams.x;
   float fogThicknessFactor = heightFogParams.y;
   float fogNoiseFactor = heightFogParams.z;
   float fogDistanceFactor = heightFogParams.w;

   float fogNoiseScaleX = heightFogParams2.x;
   float fogNoiseScaleZ = heightFogParams2.y;
   float fogNoiseSpeed = heightFogParams2.z;
   // float unused = heightFogParams2.w;

   // TODO: Re-enable fog noise after we figure out how to make it not flash around too much.
   // float fogRollingPhase = currentTime * 0.05 * fogNoiseSpeed;
   // float fogNoise = sin(fogRollingPhase + pos.x * fogNoiseScaleX) + sin(fogRollingPhase + pos.z * fogNoiseScaleZ);
   float fogNoise = 0.0;

   float normalizedHeight = smoothstep(fogHeight - 20.0, fogHeight, pos.y) + fogNoiseFactor * fogNoise / 50.0;
   float heightFactor = 1.0 - normalizedHeight;
   float distanceFactor = clamp(fogDistanceFactor, 0.0, 1.0);
   float foggyFactor = fogThicknessFactor;
   float foggyness = clamp(heightFactor * foggyFactor, 0.0, 1.0);

   fogOutColor = vec4(lightColor * heightFogColorMult.xyz * foggyness, heightFogColorMult.a * foggyness);
}

[[FS]]
#version 410
layout(location = 0) out vec4 fragData_0;
layout(location = 1) out vec4 fragData_1;
#include "shaders/utilityLib/psCommon.glsl"

const float worldRadius = 6000.0;
uniform vec3 camViewerPos;
uniform vec4 heightFogParams;
uniform vec3 lightColor;

in vec3 col0;
in vec3 col1;
in vec4 fogOutColor;
in vec4 worldPosition;

void main (void)
{
   // Scattering
   fragData_0 = vec4((col0 + 0.0325 * col1), 1.0);

   // Height Fog
   vec3 bsoffset = vec3(0.0, worldRadius, 0.0);
   vec3 v3Pos = (1.0 * worldPosition.xyz) + bsoffset;
   vec3 v3CameraPos = (1.0 * camViewerPos) + bsoffset;
   float fFar = clamp(length(v3Pos - v3CameraPos) / heightFogParams.w, 0.0, 1.0);
   fFar = smoothstep(0.0, 1.0, fFar);

   fragData_1 = fogOutColor * fFar;
}
