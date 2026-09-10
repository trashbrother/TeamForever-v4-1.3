#ifdef __APPLE__

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdio.h>
#include "metalPostprocess.hpp"

const CRTSettings crtDefaultSettings = {
    true, // enabled
    1.0f, // curvature
    1.0f, // beam
    1.0f, // mask
    1.0f, // bloom
    1.0f, // convergence
    1.0f  // vignette
};

CRTSettings crtSettings      = crtDefaultSettings;
CRTSettings crtSavedSettings = crtDefaultSettings;

void metalPostprocessProbe(void *encoderPtr)
{
    if (!encoderPtr)
        return;

    id<MTLRenderCommandEncoder> encoder =
        (__bridge id<MTLRenderCommandEncoder>)encoderPtr;

    [encoder pushDebugGroup:@"RSDKv4 Metal Postprocess Probe"];
    [encoder popDebugGroup];
}

void metalLayerProbe(void *layerPtr)
{
    static bool checked = false;

    if (checked)
        return;

    FILE *f = fopen("/tmp/rsdkv4-metal-layer.txt", "w");
    if (!f)
        return;

    if (!layerPtr) {
        fprintf(f, "layer: NULL\n");
    }
    else {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)layerPtr;

        fprintf(f, "layer: non-null\n");
        fprintf(f, "pixelFormat: %lu\n",
                (unsigned long)layer.pixelFormat);
        fprintf(f, "drawableWidth: %.0f\n",
                layer.drawableSize.width);
        fprintf(f, "drawableHeight: %.0f\n",
                layer.drawableSize.height);
        fprintf(f, "framebufferOnly: %d\n",
                layer.framebufferOnly ? 1 : 0);
        fprintf(f, "opaque: %d\n",
                layer.opaque ? 1 : 0);
    }

    fclose(f);
    checked = true;
}

void metalCopyProbe(void *encoderPtr, void *layerPtr, void *texturePtr)
{
    if (!encoderPtr || !layerPtr || !texturePtr)
        return;

    id<MTLRenderCommandEncoder> encoder =
        (__bridge id<MTLRenderCommandEncoder>)encoderPtr;
    CAMetalLayer *layer =
        (__bridge CAMetalLayer *)layerPtr;
    id<MTLTexture> texture =
        (__bridge id<MTLTexture>)texturePtr;

    static id<MTLRenderPipelineState> pipeline = nil;
    static id<MTLSamplerState> sampler = nil;
    static bool attempted = false;

    if (!attempted) {
        attempted = true;

        static NSString *shaderSource =
            @"#include <metal_stdlib>\n"
             "using namespace metal;\n"
             "\n"
             "struct VSOut {\n"
             "    float4 position [[position]];\n"
             "    float2 uv;\n"
             "};\n"
             "\n"
             "vertex VSOut rsdkCopyVertex(uint vid [[vertex_id]]) {\n"
             "    const float2 pos[6] = {\n"
             "        float2(-1.0,  1.0),\n"
             "        float2( 1.0,  1.0),\n"
             "        float2(-1.0, -1.0),\n"
             "        float2(-1.0, -1.0),\n"
             "        float2( 1.0,  1.0),\n"
             "        float2( 1.0, -1.0)\n"
             "    };\n"
             "    const float2 uv[6] = {\n"
             "        float2(0.0, 0.0),\n"
             "        float2(1.0, 0.0),\n"
             "        float2(0.0, 1.0),\n"
             "        float2(0.0, 1.0),\n"
             "        float2(1.0, 0.0),\n"
             "        float2(1.0, 1.0)\n"
             "    };\n"
             "    VSOut out;\n"
             "    out.position = float4(pos[vid], 0.0, 1.0);\n"
             "    out.uv = uv[vid];\n"
             "    return out;\n"
             "}\n"
             "\n"
             "fragment float4 rsdkCopyFragment(\n"
             "    VSOut in [[stage_in]],\n"
             "    texture2d<float> src [[texture(0)]],\n"
             "    sampler samp [[sampler(0)]]) {\n"
             "    float2 texSize = float2(src.get_width(), src.get_height());\n"
             "    float2 texel = 1.0 / texSize;\n"
             "\n"
             "    float2 warpedUV = in.uv * 2.0 - 1.0;\n"
             "    const float warpX = 0.009;\n"
             "    const float warpY = 0.012;\n"
             "    float asymX = 0.00035 * warpedUV.y * warpedUV.y * warpedUV.y;\n"
             "    warpedUV *= float2(1.0 + warpedUV.y * warpedUV.y * warpX + asymX,\n"
             "                       1.0 + warpedUV.x * warpedUV.x * warpY);\n"
             "    warpedUV = warpedUV * 0.5 + 0.5;\n"
             "\n"
             "    if (warpedUV.x < 0.0 || warpedUV.x > 1.0 ||\n"
             "        warpedUV.y < 0.0 || warpedUV.y > 1.0)\n"
             "        return float4(0.0, 0.0, 0.0, 1.0);\n"
             "\n"
             "    float sourceX = warpedUV.x * texSize.x - 0.5;\n"
             "    float baseX = floor(sourceX);\n"
             "    float fx = fract(sourceX);\n"
             "\n"
             "    float sourceY = warpedUV.y * texSize.y - 0.5;\n"
             "    float baseY = floor(sourceY);\n"
             "    float fy = fract(sourceY);\n"
             "\n"
             "    float sampleY0 = (baseY + 0.5) * texel.y;\n"
             "    float sampleY1 = (baseY + 1.5) * texel.y;\n"
             "\n"
             "    float x0 = (baseX - 1.0 + 0.5) * texel.x;\n"
             "    float x1 = (baseX       + 0.5) * texel.x;\n"
             "    float x2 = (baseX + 1.0 + 0.5) * texel.x;\n"
             "    float x3 = (baseX + 2.0 + 0.5) * texel.x;\n"
             "\n"
             "    float4 c00 = src.sample(samp, float2(x0, sampleY0));\n"
             "    float4 c01 = src.sample(samp, float2(x1, sampleY0));\n"
             "    float4 c02 = src.sample(samp, float2(x2, sampleY0));\n"
             "    float4 c03 = src.sample(samp, float2(x3, sampleY0));\n"
             "\n"
             "    float4 c10 = src.sample(samp, float2(x0, sampleY1));\n"
             "    float4 c11 = src.sample(samp, float2(x1, sampleY1));\n"
             "    float4 c12 = src.sample(samp, float2(x2, sampleY1));\n"
             "    float4 c13 = src.sample(samp, float2(x3, sampleY1));\n"
             "\n"
             "    float fx2 = fx * fx;\n"
             "    float fx3 = fx2 * fx;\n"
             "\n"
             "    float w0 = -0.5 * fx3 + fx2 - 0.5 * fx;\n"
             "    float w1 =  1.5 * fx3 - 2.5 * fx2 + 1.0;\n"
             "    float w2 = -1.5 * fx3 + 2.0 * fx2 + 0.5 * fx;\n"
             "    float w3 =  0.5 * fx3 - 0.5 * fx2;\n"
             "\n"
             "    float2 convergencePos = warpedUV * 2.0 - 1.0;\n"
             "    float convergence = 0.035 * convergencePos.x * abs(convergencePos.x);\n"
             "\n"
             "    float dw0 = -1.5 * fx2 + 2.0 * fx - 0.5;\n"
             "    float dw1 =  4.5 * fx2 - 5.0 * fx;\n"
             "    float dw2 = -4.5 * fx2 + 4.0 * fx + 0.5;\n"
             "    float dw3 =  1.5 * fx2 - fx;\n"
             "\n"
             "    float4 raw0 = c00*w0 + c01*w1 + c02*w2 + c03*w3;\n"
             "    float4 raw1 = c10*w0 + c11*w1 + c12*w2 + c13*w3;\n"
             "\n"
             "    float derivR0 = c00.r*dw0 + c01.r*dw1 + c02.r*dw2 + c03.r*dw3;\n"
             "    float derivR1 = c10.r*dw0 + c11.r*dw1 + c12.r*dw2 + c13.r*dw3;\n"
             "    float derivB0 = c00.b*dw0 + c01.b*dw1 + c02.b*dw2 + c03.b*dw3;\n"
             "    float derivB1 = c10.b*dw0 + c11.b*dw1 + c12.b*dw2 + c13.b*dw3;\n"
             "\n"
             "    raw0.r -= convergence * derivR0;\n"
             "    raw1.r -= convergence * derivR1;\n"
             "    raw0.b += convergence * derivB0;\n"
             "    raw1.b += convergence * derivB1;\n"
             "\n"
             "    float4 color0 = clamp(raw0, min(c01, c02), max(c01, c02));\n"
             "    float4 color1 = clamp(raw1, min(c11, c12), max(c11, c12));\n"
             "\n"
             "    float3 horiz0 = 0.5 * (c01.rgb + c02.rgb);\n"
             "    float3 horiz1 = 0.5 * (c11.rgb + c12.rgb);\n"
             "\n"
             "    color0.rgb = pow(max(color0.rgb, float3(0.0)), float3(2.2));\n"
             "    color1.rgb = pow(max(color1.rgb, float3(0.0)), float3(2.2));\n"
             "    horiz0 = pow(max(horiz0, float3(0.0)), float3(2.2));\n"
             "    horiz1 = pow(max(horiz1, float3(0.0)), float3(2.2));\n"
             "\n"
             "    float baseEnergy0 = clamp(dot(color0.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);\n"
             "    float baseEnergy1 = clamp(dot(color1.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);\n"
             "\n"
             "    float2 focusPos = warpedUV * 2.0 - 1.0;\n"
             "    float focusRadius = clamp(dot(focusPos, focusPos), 0.0, 1.0);\n"
             "    float edgeFocus = 0.015 * focusRadius;\n"
             "\n"
             "    float localGlow0 = 0.015 * smoothstep(0.55, 1.0, baseEnergy0);\n"
             "    float localGlow1 = 0.015 * smoothstep(0.55, 1.0, baseEnergy1);\n"
             "\n"
             "    float spotMix0 = 0.04 * baseEnergy0 + edgeFocus + localGlow0;\n"
             "    float spotMix1 = 0.04 * baseEnergy1 + edgeFocus + localGlow1;\n"
             "\n"
             "    color0.rgb = mix(color0.rgb, horiz0, spotMix0);\n"
             "    color1.rgb = mix(color1.rgb, horiz1, spotMix1);\n"
             "\n"
             "    float spotEnergy0 = clamp(dot(color0.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);\n"
             "    float spotEnergy1 = clamp(dot(color1.rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);\n"
             "\n"
             "    float width0 = mix(0.42, 0.68, spotEnergy0);\n"
             "    float width1 = mix(0.42, 0.68, spotEnergy1);\n"
             "\n"
             "    float rowPhase0 = fmod(fmod(baseY, 2.0) + 2.0, 2.0);\n"
             "    float rowPhase1 = fmod(fmod(baseY + 1.0, 2.0) + 2.0, 2.0);\n"
             "    float rowScale0 = mix(0.988, 1.012, rowPhase0);\n"
             "    float rowScale1 = mix(0.988, 1.012, rowPhase1);\n"
             "    width0 *= rowScale0;\n"
             "    width1 *= rowScale1;\n"
             "\n"
             "    float d0 = 0.90 * fy / (width0 + 0.0000001);\n"
             "    float d1 = 0.90 * (1.0 - fy) / (width1 + 0.0000001);\n"
             "\n"
             "    float shape0 = mix(2.35, 1.90, spotEnergy0);\n"
             "    float shape1 = mix(2.35, 1.90, spotEnergy1);\n"
             "\n"
             "    float beamRaw0 = exp(-pow(abs(d0), shape0));\n"
             "    float beamRaw1 = exp(-pow(abs(d1), shape1));\n"
             "\n"
             "    float darkSupport0 = 0.015 * (1.0 - spotEnergy0);\n"
             "    float darkSupport1 = 0.015 * (1.0 - spotEnergy1);\n"
             "    float beam0 = max(beamRaw0, darkSupport0);\n"
             "    float beam1 = max(beamRaw1, darkSupport1);\n"
             "\n"
             "    float slope0 = -beamRaw0 * shape0\n"
             "        * pow(max(abs(d0), 0.000001), shape0 - 1.0)\n"
             "        * (0.90 / (width0 + 0.0000001));\n"
             "    float slope1 = beamRaw1 * shape1\n"
             "        * pow(max(abs(d1), 0.000001), shape1 - 1.0)\n"
             "        * (0.90 / (width1 + 0.0000001));\n"
             "\n"
             "    slope0 *= step(darkSupport0, beamRaw0);\n"
             "    slope1 *= step(darkSupport1, beamRaw1);\n"
             "\n"
             "    float verticalConvergence =\n"
             "        0.010 * convergencePos.y * abs(convergencePos.y);\n"
             "\n"
             "    float redSlope = color0.r * slope0 + color1.r * slope1;\n"
             "    float blueSlope = color0.b * slope0 + color1.b * slope1;\n"
             "\n"
             "    float4 color;\n"
             "    color.rgb = color0.rgb * beam0 + color1.rgb * beam1;\n"
             "    color.r -= verticalConvergence * redSlope;\n"
             "    color.b += verticalConvergence * blueSlope;\n"
             "\n"
             "    float signalLuma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));\n"
             "    float3 signalGray = float3(signalLuma);\n"
             "\n"
             "    float saturation = mix(1.02, 1.06, clamp(signalLuma, 0.0, 1.0));\n"
             "    color.rgb = mix(signalGray, color.rgb, saturation);\n"
             "\n"
             "    color.rgb = (color.rgb - signalGray) * 1.02 + signalGray;\n"
             "\n"
             "    float shapedLuma = dot(max(color.rgb, float3(0.0)), float3(0.2126, 0.7152, 0.0722));\n"
             "    float highlightMix = smoothstep(0.65, 1.0, shapedLuma);\n"
             "    float rolledLuma = shapedLuma / (1.0 + 0.20 * max(shapedLuma - 0.65, 0.0));\n"
             "    float highlightGain = rolledLuma / (shapedLuma + 0.0000001);\n"
             "    color.rgb *= mix(1.0, highlightGain, highlightMix);\n"
             "\n"
             "    float2 outputPixel = floor(in.position.xy);\n"
             "    float maskY = fmod(outputPixel.y, 2.0);\n"
             "    float maskStrength = mix(0.18, 0.11, smoothstep(0.55, 1.0, shapedLuma));\n"
             "\n"
             "    float maskPhase = fmod(outputPixel.x + 2.0 * maskY, 6.0);\n"
             "\n"
             "    float dR = abs(maskPhase - 0.5);\n"
             "    float dG = abs(maskPhase - 2.5);\n"
             "    float dB = abs(maskPhase - 4.5);\n"
             "\n"
             "    dR = min(dR, 6.0 - dR);\n"
             "    dG = min(dG, 6.0 - dG);\n"
             "    dB = min(dB, 6.0 - dB);\n"
             "\n"
             "    float phosphorSigma = 0.85;\n"
             "    float invSigma2 = 1.0 / (phosphorSigma * phosphorSigma);\n"
             "\n"
             "    float3 phosphor = exp(-0.5 * float3(dR*dR, dG*dG, dB*dB) * invSigma2);\n"
             "    float3 mask = float3(1.0 - maskStrength) + phosphor * maskStrength;\n"
             "\n"
             "    color.rgb *= mask;\n"
             "    color.rgb *= 1.12;\n"
             "\n"
             "    float2 vignettePos = warpedUV * 2.0 - 1.0;\n"
             "    float vignetteRadius = dot(vignettePos, vignettePos);\n"
             "    float vignette = 1.0 - 0.055 * vignetteRadius;\n"
             "\n"
             "    float2 edgePos = abs(vignettePos);\n"
             "    float cornerX = smoothstep(0.82, 1.0, edgePos.x);\n"
             "    float cornerY = smoothstep(0.82, 1.0, edgePos.y);\n"
             "    float faceplate = 1.0 - 0.035 * cornerX * cornerY;\n"
             "\n"
             "    color.rgb *= clamp(vignette, 0.88, 1.0) * faceplate;\n"
             "\n"
             "    color.rgb = pow(max(color.rgb, float3(0.0)), float3(1.0 / 2.2));\n"
             "    color.a = 1.0;\n"
             "    return color;\n"
             "}\n";

        NSError *error = nil;
        id<MTLLibrary> library =
            [layer.device newLibraryWithSource:shaderSource
                                       options:nil
                                         error:&error];

        if (library != nil) {
            id<MTLFunction> vertexFunction =
                [library newFunctionWithName:@"rsdkCopyVertex"];
            id<MTLFunction> fragmentFunction =
                [library newFunctionWithName:@"rsdkCopyFragment"];

            if (vertexFunction != nil && fragmentFunction != nil) {
                MTLRenderPipelineDescriptor *desc =
                    [[MTLRenderPipelineDescriptor alloc] init];

                desc.label = @"RSDKv4 Metal Copy Probe";
                desc.vertexFunction = vertexFunction;
                desc.fragmentFunction = fragmentFunction;
                desc.colorAttachments[0].pixelFormat = layer.pixelFormat;

                pipeline =
                    [layer.device newRenderPipelineStateWithDescriptor:desc
                                                                error:&error];

                MTLSamplerDescriptor *samplerDesc =
                    [[MTLSamplerDescriptor alloc] init];

                samplerDesc.minFilter = MTLSamplerMinMagFilterNearest;
                samplerDesc.magFilter = MTLSamplerMinMagFilterNearest;
                samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
                samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;

                sampler = [layer.device newSamplerStateWithDescriptor:samplerDesc];
            }
        }

        FILE *f = fopen("/tmp/rsdkv4-metal-copy.txt", "w");
        if (f) {
            fprintf(f, "pipeline: %s\n", pipeline ? "non-null" : "NULL");
            fprintf(f, "sampler: %s\n", sampler ? "non-null" : "NULL");
            fprintf(f, "textureWidth: %lu\n", (unsigned long)texture.width);
            fprintf(f, "textureHeight: %lu\n", (unsigned long)texture.height);
            if (error)
                fprintf(f, "error: %s\n",
                        [[error localizedDescription] UTF8String]);
            fclose(f);
        }
    }

    if (!pipeline || !sampler)
        return;

    MTLViewport viewport;
    viewport.originX = 0.0;
    viewport.originY = 0.0;
    viewport.width = layer.drawableSize.width;
    viewport.height = layer.drawableSize.height;
    viewport.znear = 0.0;
    viewport.zfar = 1.0;

    MTLScissorRect scissor;
    scissor.x = 0;
    scissor.y = 0;
    scissor.width = (NSUInteger)layer.drawableSize.width;
    scissor.height = (NSUInteger)layer.drawableSize.height;

    [encoder pushDebugGroup:@"RSDKv4 Metal Copy Probe"];
    [encoder setViewport:viewport];
    [encoder setScissorRect:scissor];
    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6];
    [encoder popDebugGroup];
}

void metalCompositeProbe(void *encoderPtr, void *layerPtr,
                         void *texturePtr, void *diffuseTexturePtr)
{
    if (!encoderPtr || !layerPtr || !texturePtr || !diffuseTexturePtr)
        return;

    id<MTLRenderCommandEncoder> encoder =
        (__bridge id<MTLRenderCommandEncoder>)encoderPtr;
    CAMetalLayer *layer =
        (__bridge CAMetalLayer *)layerPtr;
    id<MTLTexture> texture =
        (__bridge id<MTLTexture>)texturePtr;
    id<MTLTexture> diffuseTexture =
        (__bridge id<MTLTexture>)diffuseTexturePtr;

    static id<MTLRenderPipelineState> pipeline = nil;
    static id<MTLSamplerState> sampler = nil;
    static bool attempted = false;

    if (!attempted) {
        attempted = true;

        static NSString *shaderSource =
            @"#include <metal_stdlib>\n"
             "using namespace metal;\n"
             "\n"
             "struct VSOut {\n"
             "    float4 position [[position]];\n"
             "    float2 uv;\n"
             "};\n"
             "\n"
             "vertex VSOut rsdkCompositeVertex(uint vid [[vertex_id]]) {\n"
             "    const float2 pos[6] = {\n"
             "        float2(-1.0,  1.0),\n"
             "        float2( 1.0,  1.0),\n"
             "        float2(-1.0, -1.0),\n"
             "        float2(-1.0, -1.0),\n"
             "        float2( 1.0,  1.0),\n"
             "        float2( 1.0, -1.0)\n"
             "    };\n"
             "    const float2 uv[6] = {\n"
             "        float2(0.0, 0.0),\n"
             "        float2(1.0, 0.0),\n"
             "        float2(0.0, 1.0),\n"
             "        float2(0.0, 1.0),\n"
             "        float2(1.0, 0.0),\n"
             "        float2(1.0, 1.0)\n"
             "    };\n"
             "    VSOut out;\n"
             "    out.position = float4(pos[vid], 0.0, 1.0);\n"
             "    out.uv = uv[vid];\n"
             "    return out;\n"
             "}\n"
             "\n"
             "fragment float4 rsdkCompositeFragment(\n"
             "    VSOut in [[stage_in]],\n"
             "    texture2d<float> narrowSrc [[texture(0)]],\n"
             "    texture2d<float> wideSrc [[texture(1)]],\n"
             "    sampler samp [[sampler(0)]],\n"
             "    constant float &bloomIntensity [[buffer(0)]]) {\n"
             "    float3 narrowGlow = narrowSrc.sample(samp, in.uv).rgb;\n"
             "    float3 wideGlow = wideSrc.sample(samp, in.uv).rgb;\n"
             "\n"
             "    float4 glow;\n"
             "    glow.rgb = (narrowGlow * 0.10 + wideGlow * 0.04) * bloomIntensity;\n"
             "    glow.a = 1.0;\n"
             "    return glow;\n"
             "}\n";

        NSError *error = nil;
        id<MTLLibrary> library =
            [layer.device newLibraryWithSource:shaderSource
                                       options:nil
                                         error:&error];

        if (library) {
            id<MTLFunction> vertexFunction =
                [library newFunctionWithName:@"rsdkCompositeVertex"];
            id<MTLFunction> fragmentFunction =
                [library newFunctionWithName:@"rsdkCompositeFragment"];

            if (vertexFunction && fragmentFunction) {
                MTLRenderPipelineDescriptor *desc =
                    [[MTLRenderPipelineDescriptor alloc] init];

                desc.label = @"RSDKv4 CRT Composite Probe";
                desc.vertexFunction = vertexFunction;
                desc.fragmentFunction = fragmentFunction;
                desc.colorAttachments[0].pixelFormat = layer.pixelFormat;

                desc.colorAttachments[0].blendingEnabled = YES;
                desc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
                desc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
                desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
                desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
                desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
                desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorZero;

                pipeline =
                    [layer.device newRenderPipelineStateWithDescriptor:desc
                                                                error:&error];
            }
        }

        MTLSamplerDescriptor *samplerDesc =
            [[MTLSamplerDescriptor alloc] init];

        samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;

        sampler = [layer.device newSamplerStateWithDescriptor:samplerDesc];
    }

    if (!pipeline || !sampler)
        return;

    MTLViewport viewport;
    viewport.originX = 0.0;
    viewport.originY = 0.0;
    viewport.width = layer.drawableSize.width;
    viewport.height = layer.drawableSize.height;
    viewport.znear = 0.0;
    viewport.zfar = 1.0;

    MTLScissorRect scissor;
    scissor.x = 0;
    scissor.y = 0;
    scissor.width = (NSUInteger)layer.drawableSize.width;
    scissor.height = (NSUInteger)layer.drawableSize.height;

    [encoder pushDebugGroup:@"RSDKv4 CRT Composite Probe"];
    [encoder setViewport:viewport];
    [encoder setScissorRect:scissor];
    [encoder setRenderPipelineState:pipeline];

    float bloomIntensity = crtSettings.bloom;
    [encoder setFragmentBytes:&bloomIntensity
                       length:sizeof(bloomIntensity)
                      atIndex:0];

    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentTexture:diffuseTexture atIndex:1];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6];
    [encoder popDebugGroup];
}

void *metalMultipassProbe(void *commandBufferPtr, void *layerPtr,
                          void *texturePtr, void **diffuseTextureOut)
{
    if (diffuseTextureOut)
        *diffuseTextureOut = NULL;

    if (!commandBufferPtr || !layerPtr || !texturePtr)
        return NULL;

    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)commandBufferPtr;
    CAMetalLayer *layer =
        (__bridge CAMetalLayer *)layerPtr;
    id<MTLTexture> sourceTexture =
        (__bridge id<MTLTexture>)texturePtr;

    static id<MTLTexture> offscreenTexture = nil;
    static id<MTLTexture> diffuseTexture = nil;
    static id<MTLRenderPipelineState> pipeline = nil;
    static id<MTLSamplerState> sampler = nil;
    static NSUInteger offscreenWidth = 0;
    static NSUInteger offscreenHeight = 0;
    static NSUInteger diffuseWidth = 0;
    static NSUInteger diffuseHeight = 0;
    static MTLPixelFormat offscreenFormat = MTLPixelFormatInvalid;
    static MTLPixelFormat diffuseFormat = MTLPixelFormatInvalid;
    static bool attemptedPipeline = false;

    NSUInteger width =
        MAX((NSUInteger)1, (NSUInteger)layer.drawableSize.width / 4);
    NSUInteger height =
        MAX((NSUInteger)1, (NSUInteger)layer.drawableSize.height / 4);

    if (!offscreenTexture ||
        offscreenWidth != width ||
        offscreenHeight != height ||
        offscreenFormat != layer.pixelFormat) {

        MTLTextureDescriptor *desc =
            [MTLTextureDescriptor
                texture2DDescriptorWithPixelFormat:layer.pixelFormat
                                             width:width
                                            height:height
                                         mipmapped:NO];

        desc.storageMode = MTLStorageModePrivate;
        desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

        offscreenTexture =
            [layer.device newTextureWithDescriptor:desc];

        offscreenTexture.label = @"RSDKv4 CRT Offscreen Probe";

        offscreenWidth = width;
        offscreenHeight = height;
        offscreenFormat = layer.pixelFormat;
    }

    NSUInteger wideWidth = MAX((NSUInteger)1, width / 4);
    NSUInteger wideHeight = MAX((NSUInteger)1, height / 4);

    if (!diffuseTexture ||
        diffuseWidth != wideWidth ||
        diffuseHeight != wideHeight ||
        diffuseFormat != layer.pixelFormat) {

        MTLTextureDescriptor *diffuseDesc =
            [MTLTextureDescriptor
                texture2DDescriptorWithPixelFormat:layer.pixelFormat
                                             width:wideWidth
                                            height:wideHeight
                                         mipmapped:NO];

        diffuseDesc.storageMode = MTLStorageModePrivate;
        diffuseDesc.usage =
            MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

        diffuseTexture =
            [layer.device newTextureWithDescriptor:diffuseDesc];

        diffuseTexture.label = @"RSDKv4 CRT Wide Diffusion";

        diffuseWidth = wideWidth;
        diffuseHeight = wideHeight;
        diffuseFormat = layer.pixelFormat;
    }

    if (!attemptedPipeline) {
        attemptedPipeline = true;

        static NSString *shaderSource =
            @"#include <metal_stdlib>\n"
             "using namespace metal;\n"
             "\n"
             "struct VSOut {\n"
             "    float4 position [[position]];\n"
             "    float2 uv;\n"
             "};\n"
             "\n"
             "vertex VSOut rsdkOffscreenVertex(uint vid [[vertex_id]]) {\n"
             "    const float2 pos[6] = {\n"
             "        float2(-1.0,  1.0),\n"
             "        float2( 1.0,  1.0),\n"
             "        float2(-1.0, -1.0),\n"
             "        float2(-1.0, -1.0),\n"
             "        float2( 1.0,  1.0),\n"
             "        float2( 1.0, -1.0)\n"
             "    };\n"
             "    const float2 uv[6] = {\n"
             "        float2(0.0, 0.0),\n"
             "        float2(1.0, 0.0),\n"
             "        float2(0.0, 1.0),\n"
             "        float2(0.0, 1.0),\n"
             "        float2(1.0, 0.0),\n"
             "        float2(1.0, 1.0)\n"
             "    };\n"
             "    VSOut out;\n"
             "    out.position = float4(pos[vid], 0.0, 1.0);\n"
             "    out.uv = uv[vid];\n"
             "    return out;\n"
             "}\n"
             "\n"
             "fragment float4 rsdkOffscreenFragment(\n"
             "    VSOut in [[stage_in]],\n"
             "    texture2d<float> src [[texture(0)]],\n"
             "    sampler samp [[sampler(0)]]) {\n"
             "    float2 texel = 1.0 / float2(src.get_width(), src.get_height());\n"
             "\n"
             "    float4 c = src.sample(samp, in.uv) * 0.20;\n"
             "\n"
             "    c += src.sample(samp, in.uv + texel * float2( 4.0,  0.0)) * 0.10;\n"
             "    c += src.sample(samp, in.uv + texel * float2(-4.0,  0.0)) * 0.10;\n"
             "    c += src.sample(samp, in.uv + texel * float2( 0.0,  4.0)) * 0.10;\n"
             "    c += src.sample(samp, in.uv + texel * float2( 0.0, -4.0)) * 0.10;\n"
             "\n"
             "    c += src.sample(samp, in.uv + texel * float2( 3.0,  3.0)) * 0.10;\n"
             "    c += src.sample(samp, in.uv + texel * float2(-3.0,  3.0)) * 0.10;\n"
             "    c += src.sample(samp, in.uv + texel * float2( 3.0, -3.0)) * 0.10;\n"
             "    c += src.sample(samp, in.uv + texel * float2(-3.0, -3.0)) * 0.10;\n"
             "\n"
             "    float luma = dot(c.rgb, float3(0.2126, 0.7152, 0.0722));\n"
             "    float glowMask = smoothstep(0.30, 0.75, luma);\n"
             "    c.rgb *= glowMask;\n"
             "\n"
             "    return c;\n"
             "}\n";

        NSError *error = nil;
        id<MTLLibrary> library =
            [layer.device newLibraryWithSource:shaderSource
                                       options:nil
                                         error:&error];

        if (library) {
            id<MTLFunction> vertexFunction =
                [library newFunctionWithName:@"rsdkOffscreenVertex"];
            id<MTLFunction> fragmentFunction =
                [library newFunctionWithName:@"rsdkOffscreenFragment"];

            if (vertexFunction && fragmentFunction) {
                MTLRenderPipelineDescriptor *desc =
                    [[MTLRenderPipelineDescriptor alloc] init];

                desc.label = @"RSDKv4 CRT Offscreen Copy";
                desc.vertexFunction = vertexFunction;
                desc.fragmentFunction = fragmentFunction;
                desc.colorAttachments[0].pixelFormat = layer.pixelFormat;

                pipeline =
                    [layer.device newRenderPipelineStateWithDescriptor:desc
                                                                error:&error];
            }
        }

        MTLSamplerDescriptor *samplerDesc =
            [[MTLSamplerDescriptor alloc] init];
        samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;

        sampler = [layer.device newSamplerStateWithDescriptor:samplerDesc];
    }

    if (!offscreenTexture || !diffuseTexture || !pipeline || !sampler)
        return NULL;

    MTLRenderPassDescriptor *pass =
        [MTLRenderPassDescriptor renderPassDescriptor];

    pass.colorAttachments[0].texture = offscreenTexture;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:pass];

    if (!encoder)
        return NULL;

    MTLViewport viewport;
    viewport.originX = 0.0;
    viewport.originY = 0.0;
    viewport.width = width;
    viewport.height = height;
    viewport.znear = 0.0;
    viewport.zfar = 1.0;

    MTLScissorRect scissor;
    scissor.x = 0;
    scissor.y = 0;
    scissor.width = width;
    scissor.height = height;

    encoder.label = @"RSDKv4 CRT Offscreen Copy";
    [encoder setViewport:viewport];
    [encoder setScissorRect:scissor];
    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:sourceTexture atIndex:0];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6];
    [encoder endEncoding];

    MTLRenderPassDescriptor *diffusePass =
        [MTLRenderPassDescriptor renderPassDescriptor];

    diffusePass.colorAttachments[0].texture = diffuseTexture;
    diffusePass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    diffusePass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> diffuseEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:diffusePass];

    if (!diffuseEncoder)
        return NULL;

    MTLViewport diffuseViewport;
    diffuseViewport.originX = 0.0;
    diffuseViewport.originY = 0.0;
    diffuseViewport.width = wideWidth;
    diffuseViewport.height = wideHeight;
    diffuseViewport.znear = 0.0;
    diffuseViewport.zfar = 1.0;

    MTLScissorRect diffuseScissor;
    diffuseScissor.x = 0;
    diffuseScissor.y = 0;
    diffuseScissor.width = wideWidth;
    diffuseScissor.height = wideHeight;

    diffuseEncoder.label = @"RSDKv4 CRT Wide Diffusion";
    [diffuseEncoder setViewport:diffuseViewport];
    [diffuseEncoder setScissorRect:diffuseScissor];
    [diffuseEncoder setRenderPipelineState:pipeline];
    [diffuseEncoder setFragmentTexture:offscreenTexture atIndex:0];
    [diffuseEncoder setFragmentSamplerState:sampler atIndex:0];
    [diffuseEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                       vertexStart:0
                       vertexCount:6];
    [diffuseEncoder endEncoding];

    if (diffuseTextureOut)
        *diffuseTextureOut = (__bridge void *)diffuseTexture;

    return (__bridge void *)offscreenTexture;
}

void metalRenderTargetProbe(void *texturePtr)
{
    static bool checked = false;

    if (checked)
        return;

    FILE *f = fopen("/tmp/rsdkv4-metal-render-target.txt", "w");
    if (!f)
        return;

    if (!texturePtr) {
        fprintf(f, "renderTarget: NULL\n");
    }
    else {
        id<MTLTexture> texture =
            (__bridge id<MTLTexture>)texturePtr;

        fprintf(f, "renderTarget: non-null\n");
        fprintf(f, "width: %lu\n",
                (unsigned long)texture.width);
        fprintf(f, "height: %lu\n",
                (unsigned long)texture.height);
        fprintf(f, "pixelFormat: %lu\n",
                (unsigned long)texture.pixelFormat);
        fprintf(f, "framebufferOnly: %d\n",
                texture.framebufferOnly ? 1 : 0);
    }

    fclose(f);
    checked = true;
}

void metalTextureProbe(void *texturePtr)
{
    static bool checked = false;

    if (checked)
        return;

    FILE *f = fopen("/tmp/rsdkv4-metal-texture.txt", "w");
    if (!f)
        return;

    if (!texturePtr) {
        fprintf(f, "texture: NULL\n");
    }
    else {
        id<MTLTexture> texture = (__bridge id<MTLTexture>)texturePtr;
        fprintf(f, "texture: non-null\n");
        fprintf(f, "width: %lu\n", (unsigned long)texture.width);
        fprintf(f, "height: %lu\n", (unsigned long)texture.height);
        fprintf(f, "pixelFormat: %lu\n", (unsigned long)texture.pixelFormat);
    }

    fclose(f);
    checked = true;
}

#endif
