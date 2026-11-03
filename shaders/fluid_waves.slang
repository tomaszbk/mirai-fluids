// What the texture of the world of the waves of Water_Waves holds at a point
// (layer 1 of the grid fluids.WAVE_GRID): the slope of the surface, metres a
// metre along x and z, its foam and its height over the rest of the surface.
// Zero outside its region, and without it.
#ifndef FLUID_WAVES_SLANG
#define FLUID_WAVES_SLANG
#include "vfx_world_texture.slang"

struct Fluid_Waves {
    float2 slope;
    float foam;
    float height;
};

Fluid_Waves fluid_waves_at(float3 position) {
    float4 layer = vfx_world_texture("waves", position);
    Fluid_Waves w;
    // The layer keeps the normal along x and z (Water_Waves.ripple): the slope is -n.xz / n.y.
    w.slope = -layer.xy / max(sqrt(saturate(1.0 - dot(layer.xy, layer.xy))), 0.1);
    w.foam = saturate(layer.z);
    w.height = layer.w;
    return w;
}

#endif
