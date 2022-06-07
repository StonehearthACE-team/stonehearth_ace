
uniform float global_desaturate_multiplier;

vec3 desaturate(vec3 color, float amount)
{
   vec3 gray = vec3(dot(vec3(0.2126, 0.7152, 0.0722), color));
   return vec3(mix(color, gray, amount));
}

vec3 globalDesaturate(vec3 color)
{
   return desaturate(color, global_desaturate_multiplier);
}

vec4 globalDesaturateRGBA(vec4 color)
{
   color.rgb = desaturate(color.rgb, global_desaturate_multiplier);
   return color;
}
