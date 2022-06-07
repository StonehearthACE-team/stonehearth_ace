[[FX]]

sampler2D albedoMap = sampler_state
{
	Filter = Bilinear;
};

[[VS]]
#version 410
uniform   mat4    viewProjMat;
uniform   mat4    projMat;
uniform   mat4    viewMat;
uniform   mat4    worldMat;
in vec3    vertPos;
in vec2    texCoords0;
out   vec2    texCoords;


// shader resources!!
// http://o3d.googlecode.com/svn/!svn/bc/219/trunk/samples_webgl/shaders/billboard-glsl.shader

void main() {
   texCoords = texCoords0;
   mat4 worldView = viewMat * worldMat;
   gl_Position = projMat * (vec4(vertPos, 1.0) + vec4(worldView[3].xyz, 0));
}

[[FS_AMBIENT]]
#version 410
out vec4 fragColor;
uniform sampler2D albedoMap;
in vec2 texCoords;

void main() {
   vec4 color = texture(albedoMap, texCoords);
   fragColor = vec4(color.rgb, color.a * .75);
}
