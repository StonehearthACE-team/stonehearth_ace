[[FX]]

sampler2D buf0 = sampler_state
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

in vec2 texCoords;
uniform sampler2D buf0;

void main()
{
  vec4 color = texture(buf0, texCoords);

  fragColor = vec4(color.rgb * 0.7, color.a);
}
