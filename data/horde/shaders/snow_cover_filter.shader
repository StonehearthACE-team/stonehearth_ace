[[FX]]

// TODO: Consider merging this into the albedo pass for perf.

float4 gridlineColor = { 0.2, 0.2, 0.2, 1.0 };

sampler2D albedo = sampler_state
{
   Address = Clamp;
   Filter = None;
};

sampler2D depths = sampler_state
{
   Filter = None;
   Address = Clamp;
};

sampler2D normals = sampler_state
{
   Address = Clamp;
   Filter = None;
};

sampler2D fow = sampler_state
{
   Address = Clamp;
   Filter = Pixely;
};

sampler3D gridMap = sampler_state
{
   Texture = "textures/common/gridMap.dds";
   Filter = Trilinear;
};

[[VS]]
#version 410
uniform mat4 projMat;
in vec3 vertPos;
out vec2 texCoords;

void main(void)
{
   texCoords = vertPos.xy;
   gl_Position = projMat * vec4( vertPos, 1.0 );
}


[[FS]]
#version 410
out vec4 fragColor;
#include "shaders/utilityLib/camera_transforms.glsl"

in vec2 texCoords;
uniform sampler2D albedo;
uniform sampler2D depths;
uniform sampler2D normals;
uniform sampler2D fow;

uniform mat4 camProjMat;
uniform mat4 camViewMatInv;
uniform mat4 fowViewMat;

uniform sampler3D gridMap;
uniform vec4 gridlineColor;
uniform float gridActive;

uniform float snow_amount;

void main()
{
   vec4 color = texture(albedo, texCoords);
   vec3 normal = texture(normals, texCoords).xyz;

   vec3 pos = toWorldSpace(camProjMat, camViewMatInv, texCoords, texture(depths, texCoords).r);
   vec4 projFowPos = fowViewMat * vec4(pos, 1.0);
   float max_height = texture(fow, projFowPos.xy).g * 256.0;
   float height = pos.y;

   if (abs(height - max_height) < 2.0) {
      color.rgb = mix(color.rgb, vec3(1.0, 1.0, 1.0), normal.y * snow_amount);

      // Need to redo this from deferred_albedo_lod.
      // gridlineAlpha is a single float containing the global opacity of gridlines for all
      // nodes.  gridlineColor is the per-material color of the gridline to use.  Only draw
      // them if both are > 0.0.
      vec3 gridLineCoords = pos.xyz + vec3(0.5, 0, 0.5);
      float gridline = mix(1.0, texture(gridMap, gridLineCoords).a, gridActive);
      color.rgb = mix(gridlineColor.rgb, color.rgb, mix(1.0, gridline, gridlineColor.a));
   }

   fragColor = color;
}
