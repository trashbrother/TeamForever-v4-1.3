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
             "    float sourceX = in.uv.x * texSize.x - 0.5;\n"
             "    float baseX = floor(sourceX);\n"
             "    float fx = fract(sourceX);\n"
             "\n"
             "    float sourceY = in.uv.y * texSize.y - 0.5;\n"
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
             "    float3 width0 = mix(float3(0.42), float3(0.68), color0.rgb);\n"
             "    float3 width1 = mix(float3(0.42), float3(0.68), color1.rgb);\n"
             "\n"
             "    float3 d0 = 0.90 * fy / (width0 + 0.0000001);\n"
             "    float3 d1 = 0.90 * (1.0 - fy) / (width1 + 0.0000001);\n"
             "\n"
             "    float3 beam0 = exp(-d0 * d0);\n"
             "    float3 beam1 = exp(-d1 * d1);\n"
             "\n"
             "    float4 color;\n"
             "    color.rgb = color0.rgb * beam0 + color1.rgb * beam1;\n"
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
