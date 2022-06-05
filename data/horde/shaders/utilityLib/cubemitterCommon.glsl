// *************************************************************************************************
// Common functions for cubemitters; this hides the differing APIs needed for batching/instancing.
// *************************************************************************************************
in vec3 vertPos;

#ifdef DRAW_WITH_INSTANCING
  in vec4 cubeColor;
  in mat4 particleWorldMatrix;
#else
  in float parIdx;
  uniform mat4 cubeBatchTransformArray[32];
  uniform vec4 cubeBatchColorArray[32];
#endif

vec4 cubemitter_getWorldspacePos()
{

#ifdef DRAW_WITH_INSTANCING
  return particleWorldMatrix * vec4(vertPos, 1.0);
#else
  return cubeBatchTransformArray[int(parIdx)] * vec4(vertPos, 1);
#endif
}

vec4 cubemitter_getColor()
{
#ifdef DRAW_WITH_INSTANCING
  return cubeColor;
#else
  return cubeBatchColorArray[int(parIdx)];
#endif
}