[[FX]]
// Parameters:
// x: normalized game time
// y: transition factor
float4 parameters;

// Samplers
sampler2D skyGradient = sampler_state
{
   Filter = Trilinear;
   Address = Clamp;
};

sampler2D targetSkyGradient = sampler_state
{
   Filter = Trilinear;
   Address = Clamp;
};

[[VS]]
#version 410

uniform mat4 worldMat;
uniform mat4 viewProjMat;

uniform vec3 camViewerPos;

in vec3 vertPos;
in vec2 texCoords0;

out float gradient;

void main() {
  vec4 worldPos = worldMat * vec4(vertPos, 0.0);
  worldPos += vec4(camViewerPos, 1.0);
  gl_Position = viewProjMat * worldPos;
  gradient = clamp(texCoords0.y, 0.0, 1.0);
}

[[FS]]
#version 410
out vec4 fragColor;
uniform sampler2D skyGradient;
uniform sampler2D targetSkyGradient;
uniform vec4 parameters;
in float gradient;

void main() {
   vec2 uv = vec2(parameters.x, gradient);
   vec4 color = texture(skyGradient, uv);
   vec4 targetColor = texture(targetSkyGradient, uv);
   fragColor = mix(color, targetColor, parameters.y);
}
