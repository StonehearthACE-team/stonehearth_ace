uniform float snow_amount;

uniform mat4 fowViewMat;

// Currently adds snow. In the future, could add wetness, sand cover, or other effects.
vec3 colorizeByWeather(const vec3 color, sampler2D fow, const vec3 worldPosition, const vec3 normal, float isAnimated) {
   if (isAnimated < 0.5 && snow_amount > 0.0) {
      vec4 projFowPos = fowViewMat * vec4(worldPosition, 1.0);
      float maxHeight = texture(fow, projFowPos.xy).g * 256.0;
      float height = worldPosition.y;

      if (abs(height - maxHeight) < 2.0) {
         return mix(color, vec3(1.0, 1.0, 1.0), normal.y * snow_amount);
      }
   }

   return color;
}
