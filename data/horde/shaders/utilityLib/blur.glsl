
const float g_BlurFalloff = 0.15;
//const float g_Sharpness = 0.0;

// Removed the depth-sensitivity from the sampler; it causes some aliasing in the resulting
// blur, and does NOT remove the worst depth-sensitive artifacts.
//-------------------------------------------------------------------------
float BlurFunction(vec2 uv, float r, float pixelDepth, inout float w_total, sampler2D depthbuff, sampler2D ssaobuff)
{
    float c = texture(ssaobuff, uv).r;
    //float sampleDepth = texture(depthbuff, uv).r;

    //float ddiff = abs(sampleDepth - pixelDepth);
    float w = exp(-r*r*g_BlurFalloff);// - ddiff*ddiff*g_Sharpness);

    w_total += w;
    return w * c;
}
