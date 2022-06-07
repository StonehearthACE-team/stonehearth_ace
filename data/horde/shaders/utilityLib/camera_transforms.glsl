vec3 toCameraSpace(in mat4 cProjMat, in vec2 fragCoord, in float depth)
{
  vec3 result;
  vec4 projInfo = vec4(
    -2.0 / (cProjMat[0][0]),
    -2.0 / (cProjMat[1][1]),
    (1.0 - cProjMat[0][2]) / cProjMat[0][0],
    (1.0 + cProjMat[1][2]) / cProjMat[1][1]);

  result.z = depth;
  result.xy = vec2((fragCoord.xy * projInfo.xy + projInfo.zw) * result.z);

  return result;
}


vec3 toWorldSpace(in mat4 cProjMat, in mat4 cRotInv, in vec2 fragCoord, in float linear_depth)
{
  vec3 viewPos = toCameraSpace(cProjMat, fragCoord, linear_depth);
  return -(cRotInv * vec4(viewPos, -1.0)).xyz;
}