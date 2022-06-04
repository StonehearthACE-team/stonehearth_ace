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
uniform sampler2D buf0;
in vec2 texCoords;

void main( void )
{
  vec4 col = texture(buf0, texCoords);

  if (col.a == 0.0) {
  	discard;
  }
  fragColor = vec4(col.rgb, 1.0);
}
