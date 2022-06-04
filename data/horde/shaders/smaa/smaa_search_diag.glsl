/**
 * Copyright (C) 2011 Jorge Jimenez (jorge@iryoku.com)
 * Copyright (C) 2011 Belen Masia (bmasia@unizar.es)
 * Copyright (C) 2011 Jose I. Echevarria (joseignacioechevarria@gmail.com)
 * Copyright (C) 2011 Fernando Navarro (fernandn@microsoft.com)
 * Copyright (C) 2011 Diego Gutierrez (diegog@unizar.es)
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *    1. Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *
 *    2. Redistributions in binary form must reproduce the following disclaimer
 *       in the documentation and/or other materials provided with the
 *       distribution:
 *
 *      "Uses SMAA. Copyright (C) 2011 by Jorge Jimenez, Jose I. Echevarria,
 *       Belen Masia, Fernando Navarro and Diego Gutierrez."
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS
 * IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDERS OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * The views and conclusions contained in the software and documentation are
 * those of the authors and should not be interpreted as representing official
 * policies, either expressed or implied, of the copyright holders.
 */


/**
 * SMAA_MAX_SEARCH_STEPS_DIAG specifies the maximum steps performed in the
 * diagonal pattern searches, at each side of the pixel. In this case we jump
 * one pixel at time, instead of two.
 *
 * Range: [0, 20]; set it to 0 to disable diagonal processing.
 *
 * On high-end machines it is cheap (between a 0.8x and 0.9x slower for 16
 * steps), but it can have a significant impact on older machines.
 */
#define SMAA_MAX_SEARCH_STEPS_DIAG 8

#define SMAA_AREATEX_MAX_DISTANCE_DIAG 20


#define SMAA_AREATEX_PIXEL_SIZE (1.0 / vec2(160.0, 560.0))
#define SMAA_AREATEX_SUBTEX_SIZE (1.0 / 7.0)

#define SMAAMad(a, b, c) (a * b + c)

//if SMAA_GLSL_4 == 1
//define SMAAMad(a, b, c) fma(a, b, c)
//endif


//-----------------------------------------------------------------------------
// Diagonal Search Functions

/**
 * These functions allows to perform diagonal pattern searches.
 */
float SMAASearchDiag1(sampler2D edgesTex, vec2 texcoord, vec2 dir, float c) {
    vec2 pixelSize = frameBufSize.zw;
    texcoord += dir * pixelSize;
    vec2 e = vec2(0.0, 0.0);
    float i;
    for (i = 0.0; i < float(SMAA_MAX_SEARCH_STEPS_DIAG); i++) {
        e.rg = textureLod(edgesTex, texcoord, 0.0).rg;
        if (dot(e, vec2(1.0, 1.0)) < 1.9) break;
        texcoord += dir * pixelSize;
    }
    return i + float(e.g > 0.9) * c;
}

float SMAASearchDiag2(sampler2D edgesTex, vec2 texcoord, vec2 dir, float c) {
    vec2 pixelSize = frameBufSize.zw;
    texcoord += dir * pixelSize;
    vec2 e = vec2(0.0, 0.0);
    float i;
    for (i = 0.0; i < float(SMAA_MAX_SEARCH_STEPS_DIAG); i++) {
        e.g = textureLod(edgesTex, texcoord, 0.0).g;
        e.r = textureLodOffset(edgesTex, texcoord, 0.0, ivec2(1, 0)).r;
        if (dot(e, vec2(1.0, 1.0)) < 1.9) break;
        texcoord += dir * pixelSize;
    }
    return i + float(e.g > 0.9) * c;
}

/**
 * Similar to SMAAArea, this calculates the area corresponding to a certain
 * diagonal distance and crossing edges 'e'.
 */
vec2 SMAAAreaDiag(sampler2D areaTex, vec2 dist, vec2 e, float offset) {
    vec2 texcoord = float(SMAA_AREATEX_MAX_DISTANCE_DIAG) * e + dist;

    // We do a scale and bias for mapping to texel space:
    texcoord = SMAA_AREATEX_PIXEL_SIZE * texcoord + (0.5 * SMAA_AREATEX_PIXEL_SIZE);

    // Diagonal areas are on the second half of the texture:
    texcoord.x += 0.5;

    // Move to proper place, according to the subpixel offset:
    texcoord.y += SMAA_AREATEX_SUBTEX_SIZE * offset;

    // Do it!
    return textureLod(areaTex, texcoord, 0.0).rg;
}

/**
 * This searches for diagonal patterns and returns the corresponding weights.
 */
vec2 SMAACalculateDiagWeights(sampler2D edgesTex, sampler2D areaTex, vec2 texcoord, vec2 e, ivec4 subsampleIndices) {
    vec2 pixelSize = frameBufSize.zw;
    vec2 weights = vec2(0.0, 0.0);

    vec2 d;
    d.x = e.r > 0.0 ? SMAASearchDiag1(edgesTex, texcoord, vec2(-1.0,  1.0), 1.0) : 0.0;
    d.y = SMAASearchDiag1(edgesTex, texcoord, vec2(1.0, -1.0), 0.0);

    if (d.r + d.g > 2.0) { // d.r + d.g + 1 > 3
        vec4 coords = SMAAMad(vec4(-d.r, d.r, d.g, -d.g), pixelSize.xyxy, texcoord.xyxy);

        vec4 c;
        c.x = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2(-1,  0)).g;
        c.y = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2( 0,  0)).r;
        c.z = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2( 1,  0)).g;
        c.w = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2( 1, -1)).r;
        vec2 e = 2.0 * c.xz + c.yw;
        float t = float(SMAA_MAX_SEARCH_STEPS_DIAG) - 1.0;
        e *= step(d.rg, vec2(t, t));

        weights += SMAAAreaDiag(areaTex, d, e, float(subsampleIndices.z));
    }

    d.x = SMAASearchDiag2(edgesTex, texcoord, vec2(-1.0, -1.0), 0.0);
    float right = textureLodOffset(edgesTex, texcoord, 0.0, ivec2(1, 0)).r;
    d.y = right > 0.0? SMAASearchDiag2(edgesTex, texcoord, vec2(1.0, 1.0), 1.0) : 0.0;

    if (d.r + d.g > 2.0) { // d.r + d.g + 1 > 3
        vec4 coords = SMAAMad(vec4(-d.r, -d.r, d.g, d.g), pixelSize.xyxy, texcoord.xyxy);

        vec4 c;
        c.x  = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2(-1,  0)).g;
        c.y  = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2( 0, -1)).r;
        c.zw = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2( 1,  0)).gr;
        vec2 e = 2.0 * c.xz + c.yw;
        float t = float(SMAA_MAX_SEARCH_STEPS_DIAG) - 1.0;
        e *= step(d.rg, vec2(t, t));

        weights += SMAAAreaDiag(areaTex, d, e, float(subsampleIndices.w)).gr;
    }

    return weights;
}

//endif
