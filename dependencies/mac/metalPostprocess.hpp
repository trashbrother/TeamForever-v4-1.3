#ifndef METAL_POSTPROCESS_H
#define METAL_POSTPROCESS_H

struct CRTSettings {
    bool enabled;
    float curvature;
    float beam;
    float mask;
    float bloom;
    float convergence;
    float vignette;
};

extern const CRTSettings crtDefaultSettings;
extern CRTSettings crtSettings;
extern CRTSettings crtSavedSettings;

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
