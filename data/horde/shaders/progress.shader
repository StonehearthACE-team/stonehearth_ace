[[FX]]

sampler2D progressMap  = sampler_state
{
   Filter = Trilinear;
};

[[VS]]
#version 410
uniform mat4 projMat;

in vec2 vertPos;
in vec2 texCoords0;

out vec2 texCoords;

void main() {
  texCoords = texCoords0;
  gl_Position = projMat * vec4( vertPos.x, vertPos.y, 1, 1 );
}


[[FS]]
#version 410
out vec4 fragColor;

uniform sampler2D progressMap;

in vec2 texCoords;

void main() {
  fragColor = texture(progressMap, texCoords);
}
