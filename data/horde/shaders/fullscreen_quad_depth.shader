[[FX]]

sampler2D depthImage = sampler_state
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
uniform sampler2D depthImage;
in vec2 texCoords;

void main( void )
{
   gl_FragDepth = texture(depthImage, texCoords).r;
   fragColor = vec4(0.0);
}
