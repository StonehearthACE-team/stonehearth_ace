[[FX]]
// Samplers
sampler2D backgroundMap = sampler_state
{
   Filter = Pixely;
   Address = Clamp;
};

sampler2D foregroundMap = sampler_state
{
   Filter = Pixely;
   Address = Clamp;
};

sampler2D distantMap = sampler_state
{
   Filter = None;
   Address = Clamp;
};

float4 foregroundOffsetAndScale;
float4 billboardPivotAndScale;
float alpha;
float minSizePx;
float4 ambientLightColor;
float showForegroundOnDistant;  // Really bool


[[VS]]
#version 410
uniform vec2 viewPortSize;
uniform mat4 worldMat;
uniform mat4 viewMat;
uniform mat4 projMat;
uniform vec4 foregroundOffsetAndScale;
uniform vec4 billboardPivotAndScale;
uniform float minSizePx;
uniform vec4 ambientLightColor;

in vec3 vertPos;
in vec2 texCoords0;
in vec4 color;

out vec2 backgroundTexCoords;
out vec2 foregroungTexCoords;
out vec4 oColor;
out float oScale;

void main() {
   // Get texture coordinates.
   backgroundTexCoords = vec2(texCoords0.x, texCoords0.y);
   vec2 foregroundOffset = foregroundOffsetAndScale.xy;
   vec2 foregroundScale = foregroundOffsetAndScale.zw;
   foregroungTexCoords = 0.5 + (backgroundTexCoords - 0.5 - foregroundOffset) / foregroundScale;

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
uniform sampler2D backgroundMap;
uniform sampler2D foregroundMap;
uniform sampler2D distantMap;
uniform float alpha;
uniform float showForegroundOnDistant;

in vec2 backgroundTexCoords;
in vec2 foregroungTexCoords;
in vec4 oColor;
in float oScale;

void main() {
   // Mix close foreground and background.
   vec4 closeBackground = texture(backgroundMap, backgroundTexCoords);
   vec4 closeForeground = texture(foregroundMap, foregroungTexCoords);
   bool foregroundVisible = foregroungTexCoords.x >= 0.0 && foregroungTexCoords.x <= 1.0 &&
                            foregroungTexCoords.y >= 0.0 && foregroungTexCoords.y <= 1.0;
   vec4 closeComposed = vec4(mix(closeBackground.rgb, closeForeground.rgb, closeForeground.a * float(foregroundVisible)), closeBackground.a);

   // Sample distant texture, optionally mixing in foreground.
   vec4 distant = texture(distantMap, backgroundTexCoords);
   vec4 distantComposed = vec4(mix(distant.rgb, closeForeground.rgb, closeForeground.a * float(foregroundVisible) * showForegroundOnDistant), distant.a);

   // Mix close and distant based on scale.
   float distantWeight = clamp((oScale - 1.0) * 4.0, 0.0, 1.0);
   vec4 composed = mix(closeComposed, distantComposed, distantWeight);

   // Mix in uniform alpha (for animation) and lit vertex color.
   fragColor = vec4(composed.rgb, composed.a * alpha) * oColor;

   // Discard fully transparent pixels for depth-based blending; for alpha animations, discard at 0 only.
   gl_FragDepth = composed.a > 0.5 && fragColor.a > 0.0 ? gl_FragCoord.z : 1.0;
}
