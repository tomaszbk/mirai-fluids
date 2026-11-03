//! mirai surface Wave_Surface
//! parameter color {"default":[0.02,0.08,0.1],"min":0,"max":1,"color":true}
//! parameter foam {"default":[0.9,0.9,0.9],"min":0,"max":1,"color":true}
//! parameter roughness {"default":0.05,"min":0,"max":1}
#include "fluid_waves.slang"
namespace Wave_Surface {
struct Parameters {float3 color;float roughness;float3 foam;};
// A surface of water that shows the waves of Water_Waves: the texture of the
// world of its grid, named waves, with its second layer. Its normals bend the
// surface and its foam whitens it and makes it rough. The plugin water draws
// its own water; this is what shows the waves without it.
Mirai_Surface evaluate(Mirai_Surface_Context ctx, Parameters p) {
    Mirai_Surface s=mirai_surface_default(ctx);
    Fluid_Waves waves=fluid_waves_at(ctx.world_position);
    float3 normal=normalize(float3(-waves.slope.x,1.0,-waves.slope.y));
    float foam=waves.foam;
    s.normal=normalize(ctx.normal+normal-float3(0.0,1.0,0.0));
    s.base_color=lerp(p.color,p.foam,foam);
    s.roughness=lerp(p.roughness,0.8,foam);
    return s;
}
}
