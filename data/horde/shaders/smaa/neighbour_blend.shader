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

sampler2D blendTex = sampler_state
{
  Address = Clamp;
  Filter = Bilinear;
};

sampler2D colorTex = sampler_state
{
  Address = Clamp;
  Filter = Bilinear;
};

[[VS]]
#version 410

uniform mat4 projMat;
uniform vec4 frameBufSize;

in vec3 vertPos;

out vec4 offset[2];
out vec2 texcoord;

void main() {
    vec2 pixelSize = frameBufSize.zw;
    gl_Position = projMat * vec4(vertPos, 1.0);

    texcoord = vertPos.xy;
    offset[0] = texcoord.xyxy + pixelSize.xyxy * vec4(-1.0, 0.0, 0.0, -1.0);
    offset[1] = texcoord.xyxy + pixelSize.xyxy * vec4( 1.0, 0.0, 0.0,  1.0);
}

[[FS]]
#version 410

uniform sampler2D colorTex;
uniform sampler2D blendTex;
uniform vec4 frameBufSize;

in vec2 texcoord;
in vec4 offset[2];
out vec4 fragColor;

void main() {
    // Fetch the blending weights for current pixel:
    vec4 a;
    a.xz = texture(blendTex, texcoord).xz;
    a.y = texture(blendTex, offset[1].zw).g;
    a.w = texture(blendTex, offset[1].xy).a;

    // Is there any blending weight with a value greater than 0.0?
    if (dot(a, vec4(1.0, 1.0, 1.0, 1.0)) < 1e-5) {
        fragColor = textureLod(colorTex, texcoord, 0.0);
    } else {
        vec2 pixelSize = frameBufSize.zw;
        vec4 color = vec4(0.0, 0.0, 0.0, 0.0);

        // Up to 4 lines can be crossing a pixel (one through each edge). We
        // favor blending by choosing the line with the maximum weight for each
        // direction:
        vec2 offset;
        offset.x = a.a > a.b? a.a : -a.b; // left vs. right
        offset.y = a.g > a.r? a.g : -a.r; // top vs. bottom

        // Then we go in the direction that has the maximum weight:
        if (abs(offset.x) > abs(offset.y)) {// horizontal vs. vertical
            offset.y = 0.0;
        } else {
            offset.x = 0.0;
        }

        //if SMAA_DIRECTX9_LINEAR_BLEND == 0
            // We exploit bilinear filtering to mix current pixel with the chosen
            // neighbor:


            fragColor = textureLod(colorTex, texcoord + offset * pixelSize, 0.0);


        /*else
            // Fetch the opposite color and lerp by hand:
            vec4 C = textureLod(colorTex, texcoord, 0.0);
            texcoord += sign(offset) * pixelSize;
            vec4 Cop = textureLod(colorTex, texcoord, 0.0);
            float s = abs(offset.x) > abs(offset.y)? abs(offset.x) : abs(offset.y);
            fragColor = mix(C, Cop, s);
        endif*/
    }
}
