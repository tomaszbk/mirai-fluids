//! mirai vfx Water_Waves
//! resource waves grid
//! resource displacers channel
//! stage ripple over waves iterations 4
//! parameter wave_speed {"default":2,"min":0,"max":20}
//! parameter damping {"default":0.4,"min":0,"max":10}
//! parameter displacement {"default":1,"min":0,"max":4}
//! parameter foam_rate {"default":0.4,"min":0,"max":16}
//! parameter foam_speed {"default":0.15,"min":0,"max":4}
//! parameter foam_fade {"default":0.6,"min":0,"max":8}
//! parameter normal_strength {"default":1,"min":0,"max":8}
//! parameter edge_width {"default":0.1,"min":0.001,"max":1}
//! parameter shore_depth {"default":0,"min":0,"max":8}
//! parameter shore_foam {"default":1,"min":0,"max":16}
// The waves and wakes on a surface of water: a field of heights over its
// rest on the cells of the grid waves, flat along y, that follows the view
// (Particle_Grid.follow_view). Its two layers:
//
//   0  the height over the rest of the surface (m), its vertical velocity
//      (m/s), the foam (0 to 1) and 1 + how deep the ground is under the rest
//      of the surface (m; 0 while not found)
//   1  what the material of the water reads as a texture of the world
//      (fluid_waves.slang): the normal of the surface along x and z, the foam
//      and the height
//
// The heights carry waves at wave_speed (the wave equation, in four steps a
// step of the particles) and lose their motion by damping, more at the edges
// of the region, which take what reaches them. The bodies of the channel
// displacers each press the surface down by their submerged volume over the
// disc they lie in, swept from where they were the step before: a body that
// moves leaves a wake. Foam comes where the water rises or falls faster than
// foam_speed, where a body pushes it and, with shore_depth, where the ground
// is less than that under the surface, and fades. A ray down from a cell
// finds that ground once, when the cell comes into the region: what stands
// under the water is taken to stay. It is presentation alone: nothing of it
// goes back to the game.
namespace Water_Waves {
struct Parameters {
    float wave_speed;      // metres a second waves run at
    float damping;         // of the vertical motion, a second
    float displacement;    // multiplies how deep the bodies press the surface
    float foam_rate;       // foam a metre a second of vertical motion beyond foam_speed gives, a second
    float foam_speed;      // metres a second of vertical motion below which the water makes no foam
    float foam_fade;       // of the foam, a second
    float normal_strength; // multiplies the slope the normals show
    float edge_width;      // share of the region its edges take the waves over
    float shore_depth;     // metres of water over the ground under which the shore foams; 0: no shore
    float shore_foam;      // foam a second the shore gives where the ground reaches the surface
};
struct Attributes { float unused; };

static const float ITERATIONS = 4.0;
static const float SHORE_OVER = 0.5;   // m over the rest of the surface the ray to the ground starts
static const float SHORE_NONE = 100.0; // what layer 0 w holds where no ground is in reach
static const float WAVES_PI = 3.14159265;
static const float FOAM_SPREAD = 0.1;  // of the foam around a cell it takes an iteration
static const float VISCOSITY = 0.001;  // of a cell squared an iteration: the speckle of a cell is gone in a second

void initialize(Mirai_Vfx_Context ctx, Parameters p, inout Mirai_Vfx_Particle particle, inout Attributes a) {}

// How far a point is from the segment from a to b.
float segment_distance(float2 u, float2 a, float2 b) {
    float2 ua = u - a, ba = b - a;
    float h = saturate(dot(ua, ba) / max(dot(ba, ba), 1e-12));
    return length(ua - ba * h);
}

// How deep the bodies of the step press a cell down, metres, and how fast
// the one that presses it most moves.
float pressed(Mirai_Vfx_Cell cell, float dt, out float speed) {
    float depth = 0.0;
    speed = 0.0;
    uint count = mirai_vfx_channel_count(cell.ctx, displacers);
    for (uint i = 0u; i < count; i++) {
        Mirai_Vfx_Birth b = mirai_vfx_channel_birth(cell.ctx, displacers, i);
        float radius = max(b.size, 1e-3);
        float2 now = b.position.xz, before = now - b.velocity.xz * dt;
        float shape = 1.0 - smoothstep(0.6 * radius, radius, segment_distance(cell.position.xz, before, now));
        if (!(shape > 0.0)) continue;
        float sunk = min(max(b.values.x, 0.0) / (WAVES_PI * radius * radius), 2.0 * radius) * shape;
        if (sunk > depth) { depth = sunk; speed = length(b.velocity.xz); }
    }
    return depth;
}

// 1 inside the region, falling to 0 over width of it at its edges.
float edge_of(Mirai_Vfx_Cell cell, float width) {
    Mirai_Vfx_Grid g = mirai_vfx_grid(cell.ctx, waves);
    float2 unit = (float2(cell.index.xz - g.first.xz) + 0.5) / float2(max(g.cells.xz, int2(1)));
    float2 inner = min(unit, 1.0 - unit) / max(width, 1e-3);
    return saturate(min(inner.x, inner.y));
}

void ripple(Mirai_Vfx_Cell cell, Parameters p) {
    float size = mirai_vfx_grid(cell.ctx, waves).cell_size;
    float dt = cell.ctx.delta_time / ITERATIONS;
    float4 here = mirai_vfx_grid_load(cell.ctx, waves, cell.index, 0u);
    float4 left = mirai_vfx_grid_load(cell.ctx, waves, cell.index - int3(1, 0, 0), 0u);
    float4 right = mirai_vfx_grid_load(cell.ctx, waves, cell.index + int3(1, 0, 0), 0u);
    float4 back = mirai_vfx_grid_load(cell.ctx, waves, cell.index - int3(0, 0, 1), 0u);
    float4 front = mirai_vfx_grid_load(cell.ctx, waves, cell.index + int3(0, 0, 1), 0u);
    float2 corners = mirai_vfx_grid_load(cell.ctx, waves, cell.index + int3(1, 0, 1), 0u).xy
        + mirai_vfx_grid_load(cell.ctx, waves, cell.index + int3(-1, 0, 1), 0u).xy
        + mirai_vfx_grid_load(cell.ctx, waves, cell.index + int3(1, 0, -1), 0u).xy
        + mirai_vfx_grid_load(cell.ctx, waves, cell.index + int3(-1, 0, -1), 0u).xy;
    // Nine points with the diagonals: waves run alike every way. Five run the short ones faster
    // along the axes and the diagonals, and a sharp push opens into a cross.
    float2 laplacian = (4.0 * (left.xy + right.xy + back.xy + front.xy) + corners - 20.0 * here.xy) / (6.0 * size * size);
    // Slower than a cell in two of the step: the waves stay stable.
    float c = min(p.wave_speed, 0.5 * size / max(dt, 1e-6));
    float speed;
    float depth = pressed(cell, cell.ctx.delta_time, speed) * p.displacement;
    float edge = edge_of(cell, p.edge_width);
    float push = depth > 0.0 ? (c * c / (size * size)) * 4.0 * (-depth - here.x) : 0.0;
    // A viscosity that takes the waves a cell or two long out within a few steps and leaves the longer
    // ones: the Laplacian carries those slowly and without loss, a speckle over the water.
    float viscosity = VISCOSITY * size * size / max(dt, 1e-6);
    float acceleration = c * c * laplacian.x + viscosity * laplacian.y - (p.damping + (1.0 - edge) * 8.0) * here.y + push;
    float velocity = here.y + acceleration * dt;
    float height = (here.x + velocity * dt) * lerp(0.98, 1.0, edge);
    float churn = abs(velocity) - p.foam_speed;
    // Foam spreads a little to the cells around: no edge a cell sharp where it fills one and not the next.
    float spread = lerp(here.z, 0.25 * (left.z + right.z + back.z + front.z), FOAM_SPREAD);
    float foam = spread * exp(-p.foam_fade * dt) + p.foam_rate * (churn * smoothstep(0.0, p.foam_speed + 1e-3, churn) + (depth > 0.0 ? speed * 0.25 : 0.0)) * dt;
    float ground = here.w;
    if (p.shore_depth > 0.0) {
        if (cell.ctx.iteration == 0u && ground == 0.0) {
            // From a little over the rest of the surface, to find a shore that rises out of it too.
            Mirai_Vfx_Hit h = mirai_vfx_trace(cell.ctx, cell.position + float3(0.0, SHORE_OVER, 0.0), float3(0.0, -1.0, 0.0), SHORE_OVER + p.shore_depth);
            ground = h.hit && !h.inside ? 1.0 + max(h.distance - SHORE_OVER, -1.0) : (h.inside ? 0.5 : SHORE_NONE);
        }
        float under = ground - 1.0;
        if (ground > 0.0 && ground < SHORE_NONE && under > -SHORE_OVER) {
            // It foams most where the ground meets the surface, and comes and goes with the waves.
            float breaking = 0.6 + 0.4 * sin(cell.ctx.time * 1.7 + dot(cell.position.xz, float2(0.9, 1.3)));
            foam += p.shore_foam * saturate(1.0 - abs(under) / p.shore_depth) * breaking * dt;
        }
    }
    foam = saturate(foam);
    mirai_vfx_grid_store(cell, 0u, float4(height, velocity, foam, ground));
    // What the material shows fades to still water over the edges, where the region the view
    // carries ends: no line where the waves stop.
    float2 slope = float2(right.x - left.x, front.x - back.x) / (2.0 * size) * p.normal_strength * edge;
    float3 normal = normalize(float3(-slope.x, 1.0, -slope.y));
    mirai_vfx_grid_store(cell, 1u, float4(normal.x, normal.z, foam * edge, height * edge));
}

void update(Mirai_Vfx_Context ctx, Parameters p, inout Mirai_Vfx_Particle particle, inout Attributes a) {}

void render(Mirai_Vfx_Context ctx, Parameters p, Mirai_Vfx_Particle particle, Attributes a, inout Mirai_Vfx_Visual visual) {}
}
