//! mirai surface Water_Fluids_Surface
//! parameter tint {"default":[1,1,1],"min":0,"max":1,"color":true}
//! parameter roughness {"default":0.02,"min":0,"max":1}
//! parameter detail {"default":1,"min":0,"max":4}
//! parameter waves {"default":1,"min":0,"max":4}
#include "water.slang"
#include "fluid_waves.slang"
namespace Water_Fluids_Surface {
struct Parameters {float3 tint;float roughness;float detail;float waves;};
// The surface of the water of the plugin water (Water_Surface) with the waves
// and wakes of the grid waves of fluids, when the world has it: the program
// water_fluids names in water.Water_Settings.
Mirai_Surface evaluate(Mirai_Surface_Context ctx, Parameters p) {
    Mirai_Surface s=mirai_surface_default(ctx);
    float2 slope=water_detail_slope(water_detail_place(ctx.world_position.xz,ctx.origin),ctx.time)*p.detail;
    slope+=fluid_waves_at(ctx.world_position).slope*p.waves;
    float3 bent=normalize(float3(-slope.x,1.0,-slope.y));
    s.normal=normalize(ctx.normal+bent-float3(0.0,1.0,0.0));
    s.base_color=p.tint;
    s.roughness=p.roughness;
    return s;
}
}
