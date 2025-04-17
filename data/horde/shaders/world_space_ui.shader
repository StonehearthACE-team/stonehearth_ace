[[FX]]
sampler2D albedo = sampler_state
{
   Filter = Trilinear;
   Address = Clamp;
};

float4 billboardPivotAndScale;
float alpha;
float minSizePx;
float4 ambientLightColor;


[[VS]]
#version 410
uniform vec2 viewPortSize;
uniform mat4 worldMat;
uniform mat4 viewMat;
uniform mat4 projMat;
uniform vec4 billboardPivotAndScale;
uniform float minSizePx;
uniform vec4 ambientLightColor;

in vec3 vertPos;
in vec2 texCoords0;
in vec4 color;

out vec2 texCoords;
out vec4 oColor;
out float oScale;

void main() {
   // Get texture coordinates.
   texCoords = vec2(texCoords0.x, texCoords0.y);

   // Scale the whole billboard.
   vec2 scaleOffset = vertPos.xy - billboardPivotAndScale.xy;
   vec2 scaledVertPos = billboardPivotAndScale.xy + scaleOffset * billboardPivotAndScale.zw;

   // Cap minimum screen size.
   vec4 worldOrigin = viewMat * worldMat * vec4(0, 0, 0, 1);
   vec4 origin = projMat * worldOrigin;
   vec2 screenScale = origin.w * minSizePx / viewPortSize;
   screenScale /= min(screenScale.x, 1.0);
   scaledVertPos *= screenScale;

   // Apply ambient light color.
   vec4 shadedColor = color;
   shadedColor.rgb *= 0.75 + 0.5 * ambientLightColor.rgb;

   // Write out the final values.
   oColor = shadedColor;
   oScale = screenScale.x;
   gl_Position = origin + vec4(scaledVertPos.xy, 0, 0);
}


[[FS]]
#version 410
out vec4 fragColor;
uniform sampler2D albedo;
uniform float alpha;

in vec2 texCoords;
in vec4 oColor;
in float oScale;

void main() {
   // Sample texture.
   vec4 albedoSample = texture(albedo, texCoords);

   // Mix in uniform alpha (for animation) and lit vertex color.
   vec4 tColor = vec4(albedoSample.rgb, albedoSample.a * alpha) * oColor;

   // *** doesn't actually work! whatever renderer is behind this flickers black when alpha is 0.0
   // this is super crude, but assume pure magenta is transparency
   // anti-aliased with black, all equal red and blue with 0 green should be treated as transparency-blended
   // if (tColor.r > 0.0 && tColor.b > 0.0 && tColor.r == tColor.b && tColor.g == 0.0) {
   //    if (tColor.r == 1.0 && tColor.b == 1.0) {
   //       //tColor.a = 0.0;
   //       discard;
   //    } else {
   //       tColor.a = tColor.r;
   //       tColor.r = tColor.b = 0.0;
   //    }
   // }

   fragColor = tColor;

   // For now, draw on top of everything.
   gl_FragDepth = fragColor.a > 0.0 ? 0.0 : 1.0;
}
