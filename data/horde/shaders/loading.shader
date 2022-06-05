[[FX]]

// Samplers
sampler2D loadingMap  = sampler_state
{
   Filter = Trilinear;
};

[[VS]]
#version 410

uniform mat4 projMat;
in vec2 vertPos;
out vec2 texCoords;

void main( void )
{
   texCoords = vec2( vertPos.x, -vertPos.y );
   gl_Position = projMat * vec4( vertPos.x, vertPos.y, 1, 1 );
}


[[FS]]
#version 410
out vec4 fragColor;

uniform sampler2D loadingMap;
in vec2 texCoords;

void main( void )
{
   vec4 albedo = texture( loadingMap, texCoords );

   fragColor = albedo;
}
