/**
 * Transforms vertices that are assumed to come from a fullscreen polygon already in view space,
 * into clip space.  Outputs texture coordinates, as well.
 */
void transform_fullscreen(
    const vec3 vertexPos,
    const mat4 projMat,
    out vec4 transformedPos,
    out vec2 texCoords) {
  texCoords = vertexPos.xy;
  transformedPos = projMat * vec4(vertexPos, 1.0);
}