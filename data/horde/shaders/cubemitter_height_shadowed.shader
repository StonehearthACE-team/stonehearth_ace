[[FX]]

sampler2D fow = sampler_state
{
   Address = Clamp;
   Filter = Pixely;
};

[[VS]]
#version 410
// Cubemitters can take two different paths for rendering (instancing, and the fallback: batching),
// so always use the cubemitter interface to get your data!

#include "shaders/utilityLib/cubemitterCommon.glsl"
#include "shaders/utilityLib/desaturate.glsl"

uniform mat4 viewProjMat;
uniform mat4 fowViewMat;

uniform sampler2D fow;

out vec4 color;
out float visible;

void main(void)
{
  color = globalDesaturateRGBA(cubemitter_getColor());
  vec4 pos = cubemitter_getWorldspacePos();
  gl_Position = viewProjMat * pos;

  vec4 projFowPos = fowViewMat * vec4(pos.xyz, 1.0);
  float max_height = texture(fow, projFowPos.xy).g * 256.0;
  float height = pos.y;
  visible = height > max_height ? 1.0 : 0.0;
}

[[FS]]
#version 410
out vec4 fragColor;
in vec4 color;
in float visible;

void main( void )
{
   if (visible > 0.5) {
      fragColor = color;
   } else {
      discard;
   }
}
