[[FX]]

sampler2D albedoMap = sampler_state
{
   Address = Wrap;
   Texture = "textures/common/white.tga";
   Filter = None;
};

[[VS]]
#version 410
uniform   mat4    viewProjMat;
uniform   mat4    worldMat;
in vec3    vertPos;
in vec2    texCoords0;
out   vec2    texCoords;

void main() {
	texCoords = texCoords0;
	gl_Position = viewProjMat * worldMat * vec4(vertPos, 1.0);
}


[[FS]]
#version 410
out vec4 fragColor;
uniform sampler2D albedoMap;
in vec2      texCoords;

void main() {
   fragColor = (1.0 - global_desaturate_multiplier) * texture2D(albedoMap, texCoords);
}
