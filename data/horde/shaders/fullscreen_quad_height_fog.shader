[[FX]]
sampler2D depths = sampler_state
{
  Address = Clamp;
  Filter = None;
};

sampler2D atmosphere = sampler_state
{
  Address = Clamp;
  Filter = None;
};

[[VS]]
#version 410
uniform mat4 projMat;
in vec3 vertPos;
out vec2 texCoords;

void main( void )
{
   texCoords = vertPos.xy;
   gl_Position = projMat * vec4( vertPos, 1.0 );
}

[[FS]]
#version 410
out vec4 fragColor;
#include "shaders/utilityLib/camera_transforms.glsl"
uniform sampler2D depths;
uniform sampler2D atmosphere;
uniform mat4 camProjMat;
uniform mat4 camViewMatInv;

uniform vec4 heightFogParams;
uniform vec4 heightFogColorMult;
uniform vec4 celestialLightColor;
uniform vec3 camViewerPos;

in vec2 texCoords;

void main( void )
{
   vec4 depthInfo = texture(depths, texCoords);
   vec3 pos = toWorldSpace(camProjMat, camViewMatInv, texCoords, depthInfo.r);

   float fFar = clamp(length(pos - camViewerPos) * heightFogParams.w, 0.0, 1.0);
   fFar = smoothstep(0.0, 1.0, fFar);
   float foggyness = texture(atmosphere, texCoords).a * fFar;
   fragColor = (celestialLightColor * heightFogColorMult) * foggyness;
}
