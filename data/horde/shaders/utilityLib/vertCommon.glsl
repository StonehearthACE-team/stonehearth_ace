// *************************************************************************************************
// Horde3D Shader Utility Library
// --------------------------------------
//		- Common functions -
//
// Copyright (C) 2006-2011 Nicolas Schulz
//
// You may use the following code in projects based on the Horde3D graphics engine.
//
// *************************************************************************************************

uniform mat4 viewMat;
uniform mat4 worldMat;
uniform	mat3 worldNormalMat;
uniform float modelScale;

#ifdef DRAW_SKINNED
in float boneIndex;
uniform mat4 bones[50];
#endif

#ifdef DRAW_WITH_INSTANCING
in mat4 transform;
#endif

vec4 calcWorldPos( const vec4 pos )
{
#ifdef DRAW_WITH_INSTANCING
	mat4 tr = transform;
#else
	mat4 tr = worldMat;
#endif
    mat4 final;
#ifdef DRAW_SKINNED
	// A certain driver vendor that shall remain nameless will do a pure virtual call if you try to put
	// the int cast right in the array lookup.
	int idx = int(boneIndex);
	final = tr * bones[idx];
#else
	final = tr;
#endif

	return final * vec4(pos.xyz * modelScale, 1.0);
}


vec4 calcViewPos( const vec4 worldPos )
{
	return viewMat * worldPos;
}

vec3 calcWorldVec( const vec3 vec )
{
#ifdef DRAW_WITH_INSTANCING
	mat4 tr = transform;
#else
	mat4 tr = worldMat;
#endif
	mat4 final;
#ifdef DRAW_SKINNED
	// A certain driver vendor that shall remain nameless will do a pure virtual call if you try to put
	// the int cast right in the array lookup.
	int idx = int(boneIndex);
	final = tr * bones[idx];
#else
	final = tr;
#endif

	return (final * vec4(vec, 0.0)).xyz;
}

float getWorldScale()
{
  return modelScale;
}

mat3 calcTanToWorldMat( const vec3 tangent, const vec3 bitangent, const vec3 normal )
{
	return mat3( tangent, bitangent, normal );
}

vec3 calcTanVec( const vec3 vec, const vec3 tangent, const vec3 bitangent, const vec3 normal )
{
	vec3 v;
	v.x = dot( vec, tangent );
	v.y = dot( vec, bitangent );
	v.z = dot( vec, normal );
	return v;
}


uniform float nearPlane;
uniform float farPlane;

// Takes a normalized depth value (as written to the depth buffer), and maps it back into [near, far].
float toLinearDepth(float d)
{
  float z_n = 2.0 * d - 1.0;
  float z_e = 2.0 * nearPlane * farPlane / (farPlane + nearPlane - z_n * (farPlane - nearPlane));
  return z_e;
}

float checkIsAnimated()
{
   #ifdef DRAW_SKINNED
      if (boneIndex > 0.0) {
         return 1.0;
      } else {
         return 0.0;
      }
   #else
      return 0.0;
   #endif
}