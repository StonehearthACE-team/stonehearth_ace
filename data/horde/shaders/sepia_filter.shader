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
uniform vec4 frameBufSize;

void main()
{
  vec4 color = vec4(0.0);
  vec2 off1 = vec2(1.3846153846) * 1.0;
  vec2 off2 = vec2(3.2307692308) * 1.0;
  color += texture(buf0, texCoords) * 0.2270270270;
  color += texture(buf0, texCoords + (off1 / frameBufSize.xy)) * 0.3162162162;
  color += texture(buf0, texCoords - (off1 / frameBufSize.xy)) * 0.3162162162;
  color += texture(buf0, texCoords + (off2 / frameBufSize.xy)) * 0.0702702703;
  color += texture(buf0, texCoords - (off2 / frameBufSize.xy)) * 0.0702702703;

  vec4 outCol;

  outCol.r = (color.r * 0.393) + (color.g * 0.769) + (color.b * 0.189);
  outCol.g = (color.r * 0.349) + (color.g * 0.686) + (color.b * 0.168);
  outCol.b = (color.r * 0.272) + (color.g * 0.534) + (color.b * 0.131);

  fragColor = vec4(outCol.rgb, color.a);
}
