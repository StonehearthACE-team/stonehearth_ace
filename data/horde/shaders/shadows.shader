
uniform mat4 shadowMats[4];
uniform sampler2DShadow shadowMap;
uniform vec4 shadowSplitDists;
uniform float shadowMapSize;
uniform float shadowFactor;

uniform mat4 camViewMat;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Private Functions
///////////////////////////////////////////////////////////////////////////////////////////////////


vec4 _shadowCoordsByMap_deferred(const vec3 worldSpace_fragmentPos) {
  vec4 cascadeTexCoord;
  vec4 hWorldSpace_fragmentPos = vec4(worldSpace_fragmentPos, 1.0);

  cascadeTexCoord = shadowMats[0] * hWorldSpace_fragmentPos;
  if (max(abs(cascadeTexCoord.x - 0.25), abs(cascadeTexCoord.y - 0.25)) <= 0.249) {
    cascadeTexCoord.z -= 0.001;
    return cascadeTexCoord;
  }

  cascadeTexCoord = shadowMats[1] * hWorldSpace_fragmentPos;
  if (max(abs(cascadeTexCoord.x - 0.75), abs(cascadeTexCoord.y - 0.25)) <= 0.249) {
    cascadeTexCoord.z -= 0.001;
    return cascadeTexCoord;
  }

  cascadeTexCoord = shadowMats[2] * hWorldSpace_fragmentPos;
  if (max(abs(cascadeTexCoord.x - 0.75), abs(cascadeTexCoord.y - 0.75)) <= 0.249) {
    cascadeTexCoord.z -= 0.001;
    return cascadeTexCoord;
  }

  return shadowMats[3] * hWorldSpace_fragmentPos;
}


vec4 _shadowCoordsByMap(const vec3 worldSpace_fragmentPos) {
  vec4 cascadeTexCoord;

  cascadeTexCoord = projShadowPos[0];
  if (max(abs(cascadeTexCoord.x - 0.25), abs(cascadeTexCoord.y - 0.25)) <= 0.249) {
    return cascadeTexCoord;
  }

  cascadeTexCoord = projShadowPos[1];
  if (max(abs(cascadeTexCoord.x - 0.75), abs(cascadeTexCoord.y - 0.25)) <= 0.249) {
    return cascadeTexCoord;
  }

  cascadeTexCoord = projShadowPos[2];
  if (max(abs(cascadeTexCoord.x - 0.75), abs(cascadeTexCoord.y - 0.75)) <= 0.249) {
    return cascadeTexCoord;
  }

  return shadowMats[3] * vec4(worldSpace_fragmentPos, 1.0);
}

int _shadowCascadeNum(const vec3 worldSpace_fragmentPos) {
  vec4 cascadeTexCoord;

  cascadeTexCoord = projShadowPos[0];
  if (max(abs(cascadeTexCoord.x - 0.25), abs(cascadeTexCoord.y - 0.25)) <= 0.249) {
    return 0;
  }

  cascadeTexCoord = projShadowPos[1];
  if (max(abs(cascadeTexCoord.x - 0.75), abs(cascadeTexCoord.y - 0.25)) <= 0.249) {
    return 1;
  }

  cascadeTexCoord = projShadowPos[2];
  if (max(abs(cascadeTexCoord.x - 0.75), abs(cascadeTexCoord.y - 0.75)) <= 0.249) {
    return 2;
  }

  return 3;
}

vec4 _shadowCoordsByDistance(const vec3 worldSpace_fragmentPos, out int cascadeNum) {
  float viewDist = -(camViewMat * vec4(worldSpace_fragmentPos, 1)).z;
  vec4 projShadow;

  if (viewDist < shadowSplitDists.x) {
    cascadeNum = 0;
    projShadow = shadowMats[0] * vec4(worldSpace_fragmentPos, 1.0);
  } else if(viewDist < shadowSplitDists.y) {
    cascadeNum = 1;
    projShadow = shadowMats[1] * vec4(worldSpace_fragmentPos, 1.0);
  } else if(viewDist < shadowSplitDists.z ) {
    cascadeNum = 2;
    projShadow = shadowMats[2] * vec4(worldSpace_fragmentPos, 1.0);
  } else {
    cascadeNum = 3;
    projShadow = shadowMats[3] * vec4(worldSpace_fragmentPos, 1.0);
  }
  return projShadow;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Public Functions
///////////////////////////////////////////////////////////////////////////////////////////////////

float getShadowValue(const vec3 worldSpace_fragmentPos)
{
  if (shadowFactor == 0.0) {
    return 1.0;
  }

  float shadowTerm;

  //vec4 projCoords = _shadowCoordsByDistance(worldSpace_fragmentPos, cascadeNum);
  vec4 projCoords = _shadowCoordsByMap(worldSpace_fragmentPos);

  shadowTerm = textureProj(shadowMap, projCoords);

  return mix(1.0, shadowTerm, shadowFactor);
}

float getShadowValue_deferred(const vec3 worldSpace_fragmentPos)
{
  if (shadowFactor == 0.0) {
    return 1.0;
  }

  vec4 projCoords = _shadowCoordsByMap_deferred(worldSpace_fragmentPos);
  return mix(1.0, textureProj(shadowMap, projCoords), shadowFactor);
}

vec3 getCascadeColor(const vec3 worldSpace_fragmentPos) {
  int cascadeNum = _shadowCascadeNum(worldSpace_fragmentPos);

  if (cascadeNum == 0) {
    return vec3(1, 0, 0);
  } else if (cascadeNum == 1) {
    return vec3(0, 1, 0);
  } else if (cascadeNum == 2) {
    return vec3(0, 0, 1);
  }

  return vec3(1, 1, 0);
}
