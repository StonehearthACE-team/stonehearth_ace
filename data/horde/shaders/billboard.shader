[[FX]]

// Samplers
sampler2D albedoMap  = sampler_state
{
	Filter = Pixely;
	Address = Clamp;
};

sampler2D backgroundMap = sampler_state
{
  Address = Clamp;
  Filter = Pixely;
};

float4 playerColor;


[[VS]]
#version 410
uniform mat4 worldMat;
uniform mat4 viewMat;
uniform mat4 projMat;

in vec3 vertPos;
in vec2 texCoords0;
in vec4 color;

out vec2 texCoords;
out vec4 oColor;

void main() {
	texCoords = vec2(texCoords0.x, texCoords0.y);
	oColor = color;
	gl_Position = projMat * ((viewMat * worldMat * vec4(0, 0, 0, 1)) + vec4(vertPos.x, vertPos.y, 0, 0));

	//gl_Position = projMat * ((viewMat * worldMat * vec4(0, vertPos.y, 0, 1)) + vec4(vertPos.x, 0, 0, 0));
}


[[FS]]
#version 410
out vec4 fragColor;
uniform sampler2D albedoMap;
uniform sampler2D backgroundMap;
uniform vec4 playerColor;

in vec2 texCoords;
in vec4 oColor;

void main() {
    vec4 foreground = texture(albedoMap, texCoords);
	if (playerColor.a != 0.0) {
		vec4 background = playerColor * texture(backgroundMap, texCoords);
		vec4 composed = vec4(mix(background.rgb, foreground.rgb, foreground.a), background.a);

		fragColor = composed * oColor;
	} else {
		fragColor = foreground * oColor;
	}
	gl_FragDepth = fragColor.a > 0.5 ? gl_FragCoord.z : 1.0;
}
