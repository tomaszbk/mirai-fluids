//! mirai surface Fluid_Ground
//! parameter color {"default":[0.45,0.45,0.45],"min":0,"max":1,"color":true}
//! parameter ink {"default":[0.05,0.25,0.8],"min":0,"max":1,"color":true}
//! parameter roughness {"default":0.8,"min":0,"max":1}
//! parameter wet_roughness {"default":0.15,"min":0,"max":1}
//! parameter darken {"default":0.5,"min":0,"max":1}
#include "vfx_world_texture.slang"
namespace Fluid_Ground {
struct Parameters {float3 color;float roughness;float3 ink;float wet_roughness;float darken;};
// The ground under a fluid: the texture of the world of its grid, named
// fluid, with its first layer (vfx.Particle_World_Texture). The density of
// the fluid tints it with ink, and where the fluid passed it stays wet:
// darker by darken and as rough as wet_roughness, while it dries.
Mirai_Surface evaluate(Mirai_Surface_Context ctx, Parameters p) {
    Mirai_Surface s=mirai_surface_default(ctx);
    float4 fluid=vfx_world_texture("fluid",ctx.world_position);
    float density=saturate(fluid.z);
    float wet=saturate(fluid.w);
    s.base_color=lerp(p.color,p.ink,density)*(1.0-p.darken*wet);
    s.roughness=lerp(p.roughness,p.wet_roughness,wet);
    return s;
}
}
