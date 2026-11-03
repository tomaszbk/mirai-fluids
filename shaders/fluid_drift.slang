//! mirai vfx Fluid_Drift
//! resource fluid grid
//! parameter follow {"default":4,"min":0,"max":100}
//! parameter sim_speed {"default":1,"min":0,"max":4}
//! parameter rise {"default":0,"min":-20,"max":20}
// Particles carried by the flow of the fluid of the grid fluid (Fluid): each
// step their velocity along x and z goes towards that of the fluid where
// they are, follow times a second, and the density there lifts them rise
// metres a second squared. sim_speed is that of the fluid.
namespace Fluid_Drift {
struct Parameters { float follow; float sim_speed; float rise; };
struct Attributes { float unused; };

void initialize(Mirai_Vfx_Context ctx, Parameters p, inout Mirai_Vfx_Particle particle, inout Attributes a) {}

void update(Mirai_Vfx_Context ctx, Parameters p, inout Mirai_Vfx_Particle particle, inout Attributes a) {
    Mirai_Vfx_Grid g = mirai_vfx_grid(ctx, fluid);
    if (!g.valid || !(ctx.delta_time > 0.0)) return;
    float4 here = mirai_vfx_grid_sample(ctx, fluid, particle.position, 0u);
    float2 flow = here.xy * p.sim_speed * g.cell_size / ctx.delta_time;
    particle.velocity.xz = lerp(flow, particle.velocity.xz, exp(-p.follow * ctx.delta_time));
    particle.velocity.y += p.rise * here.z * ctx.delta_time;
}

void render(Mirai_Vfx_Context ctx, Parameters p, Mirai_Vfx_Particle particle, Attributes a, inout Mirai_Vfx_Visual visual) {}
}
