/**
 * This allows to determine how much length should we add in the last step
 * of the searches. It takes the bilinearly interpolated edge (see
 * @PSEUDO_GATHER4), and adds 0, 1 or 2, depending on which edges and
 * crossing edges are active.
 */
float SMAASearchLength(sampler2D searchTex, vec2 e, float bias, float scale) {
    // Not required if searchTex accesses are set to point:
    // vec2 SEARCH_TEX_PIXEL_SIZE = 1.0 / vec2(66.0, 33.0);
    // e = vec2(bias, 0.0) + 0.5 * SEARCH_TEX_PIXEL_SIZE +
    //     e * vec2(scale, 1.0) * vec2(64.0, 32.0) * SEARCH_TEX_PIXEL_SIZE;
    e.r = bias + e.r * scale;
    e.g = -e.g;
    return 255.0 * textureLod(searchTex, e, 0.0).r;
}


/**
 * Horizontal/vertical search functions.
 */

float SMAASearchYDown(sampler2D edgesTex, sampler2D searchTex, vec2 texcoord, float end) {
    vec2 pixelSize = frameBufSize.zw;
    vec2 e = vec2(1.0, 0.0);
    while (texcoord.y < end &&
           e.r > 0.8281 && // Is there some edge not activated?
           e.g == 0.0) { // Or is there a crossing edge that breaks the line?
        e = textureLod(edgesTex, texcoord, 0.0).rg;
        texcoord += vec2(0.0, 2.0) * pixelSize;
    }

    texcoord.y -= 0.25 * pixelSize.y;
    texcoord.y -= pixelSize.y;
    texcoord.y -= 2.0 * pixelSize.y;
    texcoord.y += pixelSize.y * SMAASearchLength(searchTex, e.gr, 0.5, 0.5);
    return texcoord.y;
}

//-----------------------------------------------------------------------------
// Horizontal/Vertical Search Functions


float SMAASearchXLeft(sampler2D edgesTex, sampler2D searchTex, vec2 texcoord, float end) {
    vec2 pixelSize = frameBufSize.zw;
    /**
     * @PSEUDO_GATHER4
     * This texcoord has been offset by (-0.25, -0.125) in the vertex shader to
     * sample between edge, thus fetching four edges in a row.
     * Sampling with different offsets in each direction allows to disambiguate
     * which edges are active from the four fetched ones.
     */
    vec2 e = vec2(0.0, 1.0);
    while (texcoord.x > end &&
           e.g > 0.8281 && // Is there some edge not activated?
           e.r == 0.0) { // Or is there a crossing edge that breaks the line?
        e = textureLod(edgesTex, texcoord, 0.0).rg;
        texcoord -= vec2(2.0, 0.0) * pixelSize;
    }

    // We correct the previous (-0.25, -0.125) offset we applied:
    texcoord.x += 0.25 * pixelSize.x;

    // The searches are bias by 1, so adjust the coords accordingly:
    texcoord.x += pixelSize.x;

    // Disambiguate the length added by the last step:
    texcoord.x += 2.0 * pixelSize.x; // Undo last step
    texcoord.x -= pixelSize.x * SMAASearchLength(searchTex, e, 0.0, 0.5);

    return texcoord.x;
}

float SMAASearchXRight(sampler2D edgesTex, sampler2D searchTex, vec2 texcoord, float end) {
    vec2 e = vec2(0.0, 1.0);
    vec2 pixelSize = frameBufSize.zw;
    while (texcoord.x < end &&
           e.g > 0.8281 && // Is there some edge not activated?
           e.r == 0.0) { // Or is there a crossing edge that breaks the line?
        e = textureLod(edgesTex, texcoord, 0.0).rg;
        texcoord += vec2(2.0, 0.0) * pixelSize;
    }

    texcoord.x -= 0.25 * pixelSize.x;
    texcoord.x -= pixelSize.x;
    texcoord.x -= 2.0 * pixelSize.x;
    texcoord.x += pixelSize.x * SMAASearchLength(searchTex, e, 0.5, 0.5);
    return texcoord.x;
}

float SMAASearchYUp(sampler2D edgesTex, sampler2D searchTex, vec2 texcoord, float end) {
    vec2 pixelSize = frameBufSize.zw;
    vec2 e = vec2(1.0, 0.0);
    while (texcoord.y > end &&
           e.r > 0.8281 && // Is there some edge not activated?
           e.g == 0.0) { // Or is there a crossing edge that breaks the line?
        e = textureLod(edgesTex, texcoord, 0.0).rg;
        texcoord -= vec2(0.0, 2.0) * pixelSize;
    }

    texcoord.y += 0.25 * pixelSize.y;
    texcoord.y += pixelSize.y;
    texcoord.y += 2.0 * pixelSize.y;
    texcoord.y -= pixelSize.y * SMAASearchLength(searchTex, e.gr, 0.0, 0.5);
    return texcoord.y;
}