uniform mat4 projMat;

in vec3 vertPos;

out vec2 texCoords;

void main( void )
{
  texCoords = vertPos.xy;
  gl_Position = projMat * vec4(vertPos, 1.0);
}
