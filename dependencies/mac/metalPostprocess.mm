#ifdef __APPLE__

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdio.h>
#include "metalPostprocess.hpp"

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
             "    warpedUV *= float2(1.0 + warpedUV.y * warpedUV.y * warpX,\n"
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
             "    float4 raw0 = c00*w0 + c01*w1 + c02*w2 + c03*w3;\n"
             "    float4 raw1 = c10*w0 + c11*w1 + c12*w2 + c13*w3;\n"
             "\n"
             "    float4 color0 = clamp(raw0, min(c01, c02), max(c01, c02));\n"
             "    float4 color1 = clamp(raw1, min(c11, c12), max(c11, c12));\n"
             "\n"
             "    color0.rgb = pow(max(color0.rgb, float3(0.0)), float3(2.2));\n"
             "    color1.rgb = pow(max(color1.rgb, float3(0.0)), float3(2.2));\n"
             "\n"
             "    float luma0 = dot(color0.rgb, float3(0.2126, 0.7152, 0.0722));\n"
             "    float luma1 = dot(color1.rgb, float3(0.2126, 0.7152, 0.0722));\n"
             "\n"
             "    float width0 = mix(0.42, 0.68, clamp(luma0, 0.0, 1.0));\n"
             "    float width1 = mix(0.42, 0.68, clamp(luma1, 0.0, 1.0));\n"
             "\n"
             "    float d0 = 0.90 * fy / (width0 + 0.0000001);\n"
             "    float d1 = 0.90 * (1.0 - fy) / (width1 + 0.0000001);\n"
             "\n"
             "    float shape0 = mix(2.35, 1.90, clamp(luma0, 0.0, 1.0));\n"
             "    float shape1 = mix(2.35, 1.90, clamp(luma1, 0.0, 1.0));\n"
             "\n"
             "    float beam0 = exp(-pow(abs(d0), shape0));\n"
             "    float beam1 = exp(-pow(abs(d1), shape1));\n"
             "\n"
             "    float4 color;\n"
             "    color.rgb = color0.rgb * beam0 + color1.rgb * beam1;\n"
             "\n"
             "    float2 outputPixel = floor(in.position.xy);\n"
             "    float maskX = fmod(outputPixel.x, 6.0);\n"
             "    float maskY = fmod(outputPixel.y, 2.0);\n"
             "    float maskStrength = 0.18;\n"
             "\n"
             "    float subpixelX = fmod(maskX, 2.0);\n"
             "    float aperture = (subpixelX < 1.0) ? 1.0 : 0.92;\n"
             "\n"
             "    float3 mask = float3(1.0 - maskStrength);\n"
             "\n"
             "    float triad = floor(maskX / 2.0);\n"
             "    float stagger = fmod(triad + maskY, 3.0);\n"
             "\n"
             "    if (stagger < 1.0)\n"
             "        mask.r = aperture;\n"
             "    else if (stagger < 2.0)\n"
             "        mask.g = aperture;\n"
             "    else\n"
             "        mask.b = aperture;\n"
             "\n"
             "    color.rgb *= mask;\n"
             "    color.rgb *= 1.12;\n"
             "\n"
             "    float2 vignettePos = in.uv * 2.0 - 1.0;\n"
             "    float vignetteRadius = dot(vignettePos, vignettePos);\n"
             "    float vignette = 1.0 - 0.055 * vignetteRadius;\n"
             "    color.rgb *= clamp(vignette, 0.88, 1.0);\n"
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

void metalCompositeProbe(void *encoderPtr, void *layerPtr, void *texturePtr)
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
             "    texture2d<float> src [[texture(0)]],\n"
             "    sampler samp [[sampler(0)]]) {\n"
             "    float4 glow = src.sample(samp, in.uv);\n"
             "    glow.rgb *= 0.12;\n"
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
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6];
    [encoder popDebugGroup];
}

void *metalMultipassProbe(void *commandBufferPtr, void *layerPtr, void *texturePtr)
{
    if (!commandBufferPtr || !layerPtr || !texturePtr)
        return NULL;

    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)commandBufferPtr;
    CAMetalLayer *layer =
        (__bridge CAMetalLayer *)layerPtr;
    id<MTLTexture> sourceTexture =
        (__bridge id<MTLTexture>)texturePtr;

    static id<MTLTexture> offscreenTexture = nil;
    static id<MTLRenderPipelineState> pipeline = nil;
    static id<MTLSamplerState> sampler = nil;
    static NSUInteger offscreenWidth = 0;
    static NSUInteger offscreenHeight = 0;
    static MTLPixelFormat offscreenFormat = MTLPixelFormatInvalid;
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

    if (!offscreenTexture || !pipeline || !sampler)
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

    return (__bridge void *)offscreenTexture;
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
