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
