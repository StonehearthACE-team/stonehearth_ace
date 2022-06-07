uniform vec4 frameBufSize;

/**
 * Computes the outline color for the given texture coordinates and texture.  The texture should
 * be non-zero red in the places where the mesh exists.
 */
vec4 compute_outline_color(sampler2D outlineSampler, const vec2 texCoords) {
  vec4 centerColor = texture(outlineSampler, texCoords);
  if (centerColor.a == 0.0) {
    discard;
  }

  vec2 offset = frameBufSize.zw;

  float total = 0.0;

  vec3 t = texture(outlineSampler, texCoords + vec2(offset.x * 2.0, 0.0)).xyz;
  vec3 dt = centerColor.xyz - t;
  total += dot(dt, dt);

  t = texture(outlineSampler, texCoords + vec2(offset.x * -2.0, 0.0)).xyz;
  dt = centerColor.xyz - t;
  total += dot(dt, dt);

  t = texture(outlineSampler, texCoords + vec2(0.0, offset.y * -2.0)).xyz;
  dt = centerColor.xyz - t;
  total += dot(dt, dt);

  t = texture(outlineSampler, texCoords + vec2(0.0, offset.y * 2.0)).xyz;
  dt = centerColor.xyz - t;
  total += dot(dt, dt);

  if (total == 0.0) {
    discard;
  }

  return centerColor;
}
