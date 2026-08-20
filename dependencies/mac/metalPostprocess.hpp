#ifndef METAL_POSTPROCESS_H
#define METAL_POSTPROCESS_H

void metalPostprocessProbe(void *encoder);
void metalTextureProbe(void *texture);
void metalRenderTargetProbe(void *texture);
void metalLayerProbe(void *layer);
void metalCopyProbe(void *encoder, void *layer, void *texture);
void metalCompositeProbe(void *encoder, void *layer,
                         void *texture, void *diffuseTexture);
void *metalMultipassProbe(void *commandBuffer, void *layer,
                          void *texture, void **diffuseTextureOut);

#endif
