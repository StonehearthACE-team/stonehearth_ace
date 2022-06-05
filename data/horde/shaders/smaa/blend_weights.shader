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

[[FX]]

sampler2D edgesTex = sampler_state
{
  Address = Clamp;
  Filter = Bilinear;
};

sampler2D areaTex = sampler_state
{
  Address = Clamp;
  Filter = Bilinear;
};

sampler2D searchTex = sampler_state
{
  Address = Clamp;
  Filter = None;
};

[[VS]]
#version 410

#define SMAA_MAX_SEARCH_STEPS 16

uniform vec4 frameBufSize;
uniform mat4 projMat;

in vec3 vertPos;

out vec2 texcoord;
out vec2 pixcoord;
out vec4 offset[3];

void main() {
    vec2 pixelSize = frameBufSize.zw;

    texcoord = vertPos.xy;
    gl_Position = projMat * vec4(vertPos, 1.0);
    pixcoord = texcoord * frameBufSize.xy;

    // We will use these offsets for the searches later on (see @PSEUDO_GATHER4):
    offset[0] = texcoord.xyxy + pixelSize.xyxy * vec4(-0.25, -0.125,  1.25, -0.125);
    offset[1] = texcoord.xyxy + pixelSize.xyxy * vec4(-0.125, -0.25, -0.125,  1.25);

    // And these for the searches, they indicate the ends of the loops:
    offset[2] = vec4(offset[0].xz, offset[1].yw) +
                vec4(-2.0, 2.0, -2.0, 2.0) *
                pixelSize.xxyy * float(SMAA_MAX_SEARCH_STEPS);
}



[[FS]]
#version 410

#define SMAAMad(a, b, c) (a * b + c)

/*if SMAA_GLSL_4 == 1
define SMAAMad(a, b, c) fma(a, b, c)
endif*/

uniform vec4 frameBufSize;

#include "shaders/smaa/smaa_search_diag.glsl"
#include "shaders/smaa/smaa_search_hv.glsl"

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

/**
 * SMAA_CORNER_ROUNDING specifies how much sharp corners will be rounded.
 *
 * Range: [0, 100]; set it to 100 to disable corner detection.
 */
#define SMAA_CORNER_ROUNDING 25

#define SMAA_AREATEX_MAX_DISTANCE 16
#define SMAA_AREATEX_PIXEL_SIZE (1.0 / vec2(160.0, 560.0))
#define SMAA_AREATEX_SUBTEX_SIZE (1.0 / 7.0)

uniform sampler2D edgesTex;
uniform sampler2D areaTex;
uniform sampler2D searchTex;

in vec2 texcoord;
in vec2 pixcoord;
in vec4 offset[3];
out vec4 fragColor;

/**
 * Ok, we have the distance and both crossing edges. So, what are the areas
 * at each side of current edge?
 */
vec2 SMAAArea(sampler2D areaTex, vec2 dist, float e1, float e2, float offset) {

    // Rounding prevents precision errors of bilinear filtering:
    vec2 texcoord = float(SMAA_AREATEX_MAX_DISTANCE) * round(4.0 * vec2(e1, e2)) + dist;

    // We do a scale and bias for mapping to texel space:
    texcoord = SMAA_AREATEX_PIXEL_SIZE * texcoord + (0.5 * SMAA_AREATEX_PIXEL_SIZE);

    // Move to proper place, according to the subpixel offset:
    texcoord.y += SMAA_AREATEX_SUBTEX_SIZE * offset;

    // Do it!
    //if SMAA_HLSL_3 == 1
    return textureLod(areaTex, texcoord, 0.0).rg;
    //else
    //return textureLod(areaTex, texcoord, 0.0).rg;
    //endif
}

//-----------------------------------------------------------------------------
// Corner Detection Functions

void SMAADetectHorizontalCornerPattern(sampler2D edgesTex, inout vec2 weights, vec2 texcoord, vec2 d) {
    //if SMAA_CORNER_ROUNDING < 100 || SMAA_FORCE_CORNER_DETECTION == 1
        vec2 pixelSize = frameBufSize.zw;

	    vec4 coords = SMAAMad(vec4(d.x, 0.0, d.y, 0.0),
	                            pixelSize.xyxy, texcoord.xyxy);
	    vec2 e;
	    e.r = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2(0.0,  1.0)).r;
	    bool left = abs(d.x) < abs(d.y);
	    e.g = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2(0.0, -2.0)).r;
	    if (left) {
            weights *= clamp(float(SMAA_CORNER_ROUNDING) / 100.0 + 1.0 - e, 0, 1);
        }

	    e.r = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2(1.0,  1.0)).r;
	    e.g = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2(1.0, -2.0)).r;
	    if (!left) {
            weights *= clamp(float(SMAA_CORNER_ROUNDING) / 100.0 + 1.0 - e, 0, 1);
        }

    //endif
}

void SMAADetectVerticalCornerPattern(sampler2D edgesTex, inout vec2 weights, vec2 texcoord, vec2 d) {
    //if SMAA_CORNER_ROUNDING < 100 || SMAA_FORCE_CORNER_DETECTION == 1
        vec2 pixelSize = frameBufSize.zw;
        vec4 coords = SMAAMad(vec4(0.0, d.x, 0.0, d.y),
                                pixelSize.xyxy, texcoord.xyxy);
        vec2 e;
        e.r = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2( 1.0, 0.0)).g;
        bool left = abs(d.x) < abs(d.y);
        e.g = textureLodOffset(edgesTex, coords.xy, 0.0, ivec2(-2.0, 0.0)).g;
        if (left) {
            weights *= clamp(float(SMAA_CORNER_ROUNDING) / 100.0 + 1.0 - e, 0, 1);
        }

        e.r = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2( 1.0, 1.0)).g;
        e.g = textureLodOffset(edgesTex, coords.zw, 0.0, ivec2(-2.0, 1.0)).g;
        if (!left) {
            weights *= clamp(float(SMAA_CORNER_ROUNDING) / 100.0 + 1.0 - e, 0, 1);
        }
    //endif
}


void main() {
    vec2 pixelSize = frameBufSize.zw;
    ivec4 subsampleIndices = ivec4(0); // Just pass zero for SMAA 1x, see @SUBSAMPLE_INDICES.
    vec4 weights = vec4(0.0, 0.0, 0.0, 0.0);

    vec2 e = texture(edgesTex, texcoord).rg;

    if (e.g > 0.0) { // Edge at north
        //if SMAA_MAX_SEARCH_STEPS_DIAG > 0 || SMAA_FORCE_DIAGONAL_DETECTION == 1
            // Diagonals have both north and west edges, so searching for them in
            // one of the boundaries is enough.
            weights.rg = SMAACalculateDiagWeights(edgesTex, areaTex, texcoord, e, subsampleIndices);

            // We give priority to diagonals, so if we find a diagonal we skip
            // horizontal/vertical processing.
            if (dot(weights.rg, vec2(1.0, 1.0)) == 0.0) {
        //endif

        vec2 d;

        // Find the distance to the left:
        vec2 coords;
        coords.x = SMAASearchXLeft(edgesTex, searchTex, offset[0].xy, offset[2].x);
        coords.y = offset[1].y; // offset[1].y = texcoord.y - 0.25 * pixelSize.y (@CROSSING_OFFSET)
        d.x = coords.x;

        // Now fetch the left crossing edges, two at a time using bilinear
        // filtering. Sampling at -0.25 (see @CROSSING_OFFSET) enables to
        // discern what value each edge has:
        float e1 = textureLod(edgesTex, coords, 0.0).r;

        // Find the distance to the right:
        coords.x = SMAASearchXRight(edgesTex, searchTex, offset[0].zw, offset[2].y);
        d.y = coords.x;

        // We want the distances to be in pixel units (doing this here allow to
        // better interleave arithmetic and memory accesses):
        d = d / pixelSize.x - pixcoord.x;

        // SMAAArea below needs a sqrt, as the areas texture is compressed
        // quadratically:
        vec2 sqrt_d = sqrt(abs(d));

        // Fetch the right crossing edges:
        float e2 = textureLodOffset(edgesTex, coords, 0.0, ivec2(1, 0)).r;

        // Ok, we know how this pattern looks like, now it is time for getting
        // the actual area:
        weights.rg = SMAAArea(areaTex, sqrt_d, e1, e2, float(subsampleIndices.y));

        // Fix corners:
        SMAADetectHorizontalCornerPattern(edgesTex, weights.rg, texcoord, d);

        // if SMAA_MAX_SEARCH_STEPS_DIAG > 0 || SMAA_FORCE_DIAGONAL_DETECTION == 1
        } else
            e.r = 0.0; // Skip vertical processing.
        // endif
    }

    if (e.r > 0.0) { // Edge at west
        vec2 d;

        // Find the distance to the top:
        vec2 coords;
        coords.y = SMAASearchYUp(edgesTex, searchTex, offset[1].xy, offset[2].z);
        coords.x = offset[0].x; // offset[1].x = texcoord.x - 0.25 * pixelSize.x;
        d.x = coords.y;

        // Fetch the top crossing edges:
        float e1 = textureLod(edgesTex, coords, 0.0).g;

        // Find the distance to the bottom:
        coords.y = SMAASearchYDown(edgesTex, searchTex, offset[1].zw, offset[2].w);
        d.y = coords.y;

        // We want the distances to be in pixel units:
        d = d / pixelSize.y - pixcoord.y;

        // SMAAArea below needs a sqrt, as the areas texture is compressed
        // quadratically:
        vec2 sqrt_d = sqrt(abs(d));

        // Fetch the bottom crossing edges:
        float e2 = textureLodOffset(edgesTex, coords, 0.0, ivec2(0, 1)).g;

        // Get the area for this direction:
        weights.ba = SMAAArea(areaTex, sqrt_d, e1, e2, float(subsampleIndices.x));

        // Fix corners:
        SMAADetectVerticalCornerPattern(edgesTex, weights.ba, texcoord, d);
    }

    fragColor = weights;
}
