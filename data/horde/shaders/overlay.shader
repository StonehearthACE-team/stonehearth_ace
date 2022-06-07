[[FX]]

// Samplers
sampler2D albedoMap  = sampler_state
{
	Filter = Trilinear;
};


[[VS]]
#version 410

uniform mat4 projMat;
in vec2 vertPos;
in vec2 texCoords0;
out vec2 texCoords;

void main( void )
{
	texCoords = vec2( texCoords0.s, -texCoords0.t );
	gl_Position = projMat * vec4( vertPos.x, vertPos.y, 1, 1 );
}


[[FS]]
#version 410
out vec4 fragColor;

uniform vec4 olayColor;
uniform sampler2D albedoMap;
in vec2 texCoords;

void main( void )
{
	vec4 albedo = texture( albedoMap, texCoords );

	fragColor = albedo * olayColor;
}
