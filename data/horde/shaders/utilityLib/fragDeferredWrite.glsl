// *************************************************************************************************
// Horde3D Shader Utility Library
// --------------------------------------
//		- Deferred shading functions -
//
// Copyright (C) 2006-2011 Nicolas Schulz
//
// You may use the following code in projects based on the Horde3D graphics engine.
//
// *************************************************************************************************

void setMatID( const float id ) { fragData_0.a = id; }
void setPos( const vec3 pos ) { fragData_0.rgb = pos; }
void setNormal( const vec3 normal ) { fragData_1.rgb = normal; }
void setAlbedo( const vec3 albedo ) { fragData_2.rgb = albedo; }
void setSpecParams( const vec3 specCol, const float gloss ) { fragData_3.rgb = specCol; fragData_3.a = gloss; }
