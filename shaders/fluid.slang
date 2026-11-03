//! mirai vfx Fluid
//! resource fluid grid
//! resource brushes channel
//! resource volume grid
//! resource fluid_samples data 8
//! stage paint over fluid
//! stage composite over fluid
//! stage advect over fluid
//! stage diverge over fluid
//! stage pressure over fluid iterations 2
//! stage extrude over volume
//! parameter sim_speed {"default":1,"min":0,"max":4}
//! parameter velocity_feedback {"default":0.995,"min":0,"max":1}
//! parameter density_feedback {"default":0.99,"min":0,"max":1}
//! parameter divergence_mult {"default":0.5,"min":0,"max":2}
//! parameter pressure_feedback {"default":0.99,"min":0,"max":1}
//! parameter divergence_feedback {"default":1,"min":0,"max":1}
//! parameter kernel_mult {"default":1,"min":0.33,"max":1}
//! parameter kernel_offset {"default":0,"min":-5,"max":5}
//! parameter velocity_clamp {"default":2,"min":0,"max":16}
//! parameter brush_size {"default":1,"min":0,"max":16}
//! parameter brush_hardness {"default":0.3,"min":0,"max":1}
//! parameter brush_strength {"default":0.5,"min":0,"max":8}
//! parameter brush_velocity {"default":1,"min":0,"max":8}
//! parameter eraser {"default":0,"min":0,"max":1}
//! parameter puncture {"default":0,"min":0,"max":100}
//! parameter edge_width {"default":0.1,"min":0.001,"max":1}
//! parameter edge_pow {"default":1,"min":0.01,"max":8}
//! parameter wet_feedback {"default":0.9,"min":0,"max":1}
//! parameter wind {"default":[0,0],"min":-4,"max":4}
//! parameter obstacle_reach {"default":0,"min":0,"max":8}
//! parameter obstacle_weaken {"default":0,"min":0,"max":1}
//! parameter ground_reach {"default":0,"min":0,"max":64}
//! parameter downhill {"default":0,"min":0,"max":4}
//! parameter peak_height {"default":0,"min":0,"max":16}
//! parameter volume_height {"default":2,"min":0,"max":64}
//! parameter volume_below {"default":0.1,"min":0,"max":1}
//! parameter volume_spread {"default":0.5,"min":0,"max":4}
//! parameter volume_glow {"default":0,"min":0,"max":16}
//! parameter volume_noise {"default":0.4,"min":0,"max":1}
//! parameter volume_noise_size {"default":0.75,"min":0.01,"max":64}
// A fluid on a plane, after the core of FluidNinja Live 2.0 (its author let
// it be rewritten for Mirai; see docs/LICENCIAS.md): the cells of the grid
// fluid, flat along y, hold four layers, velocity in cells a step and the
// rest without units:
//
//   0  the fluid: velocity x and z, density, wetness (what the density
//      left as it passed, which dries over time)
//   1  the fluid carried a step: velocity x and z, density
//   2  pressure, divergence, obstacle and the height of the ground over the
//      plane, metres
//   3  what the brushes paint in the step: velocity x and z, density, mask
//
// Each step, in order: the brushes of the channel brushes paint (a disc that
// sweeps from where each was the step before) and so do the spans of the
// splines (values.z 1: a band along the span that flows along it at
// values.y metres a second), rays across the plane from
// each cell find the obstacles of the scene, moving bodies too, and one down
// across it the height of the ground there (terrain, foliage, meshes); the fluid
// takes what was
// carried, less the gradient of the pressure, with the density and the flow
// of the brushes and the wind; it is carried back along its velocity
// (semi-Lagrangian); its divergence is taken; and the pressure spreads it in
// two passes of a separable kernel, across and along. The edges of the region
// and the obstacles fade the fluid out; the slope of the ground carries it
// downhill and ground above the plane keeps it out, as peaks do.
//
// The births of brushes with values.z 2 are probes: they paint nothing, and
// the fluid appends to the data channel fluid_samples what it has where each
// is (fluid_probe). With a grid volume, the fluid is extruded into it as a
// medium (extrude).
namespace Fluid {
struct Parameters {
    float sim_speed;            // cells a unit of velocity carries the fluid in a step
    float velocity_feedback;    // what the fluid keeps of what it carries, each step
    float density_feedback;     // what its density keeps, each step
    float divergence_mult;
    float pressure_feedback;
    float divergence_feedback;
    float kernel_mult;          // width of the kernel of the pressure, from a third to whole
    float kernel_offset;        // narrower (above 0) or wider kernels for the pressure than for the divergence
    float velocity_clamp;       // cells a step
    float brush_size;           // multiplies the radius of each brush
    float brush_hardness;       // share of its radius a brush paints whole
    float brush_strength;       // multiplies the density of each brush
    float brush_velocity;       // share of the motion of a brush that it gives the fluid
    float eraser;               // brushes take density away instead of adding it
    float puncture;             // brushes push the fluid outwards where they paint
    float edge_width;           // share of the region its edges fade over
    float edge_pow;
    float wet_feedback;         // how fast the wetness dries
    float2 wind;                // a flow of the whole fluid, cells a step along x and z
    float obstacle_reach;       // metres from a surface of the scene where the fluid starts to meet it; 0: no obstacles
    float obstacle_weaken;      // what the fluid keeps inside an obstacle
    float ground_reach;         // metres above and below the plane in which the ground is found; 0: no ground
    float downhill;             // cells a step the fluid flows downhill on a slope of one
    float peak_height;          // metres of ground above the plane that keep the fluid out wholly; 0: none
    float volume_height;        // metres the medium of a unit of density rises over the plane
    float volume_below;         // share of that height it reaches under the plane
    float volume_spread;        // metres it widens a metre up
    float volume_glow;          // glow of the medium, by its density
    float volume_noise;         // share of the medium noise takes away
    float volume_noise_size;    // metres across the blots of the noise
};
struct Attributes { float unused; };

static const float GAUSS_KERNELS[6][15] = {
    { 0.00117, 0.0045, 0.01394, 0.035, 0.07186, 0.12, 0.1631, 0.1807, 0.1631, 0.12, 0.07186, 0.035, 0.01394, 0.0045, 0.00117 },
    { 0.0, 0.00222, 0.00876, 0.027, 0.0648, 0.121, 0.176, 0.199, 0.176, 0.121, 0.0648, 0.027, 0.00876, 0.00222, 0.0 },
    { 0.0, 0.0, 0.00276, 0.01377, 0.0478, 0.1169, 0.19945, 0.23832, 0.19945, 0.1169, 0.0478, 0.01377, 0.00276, 0.0, 0.0 },
    { 0.0, 0.0, 0.0, 0.0034, 0.0202, 0.09134, 0.22958, 0.31094, 0.22958, 0.09134, 0.0202, 0.0034, 0.0, 0.0, 0.0 },
    { 0.0, 0.0, 0.0, 0.0, 0.0106, 0.075, 0.2387, 0.351, 0.2387, 0.075, 0.0106, 0.0, 0.0, 0.0, 0.0 },
    { 0.0, 0.0, 0.0, 0.0, 0.0, 0.06136, 0.24477, 0.38774, 0.24477, 0.06136, 0.0, 0.0, 0.0, 0.0, 0.0 }};
// What the divergence weighs across the kernel: wider in the middle than a gaussian.
static const float DIVERGENCE_KERNELS[6][15] = {
    { 0.0006, 0.003, 0.01, 0.028, 0.064, 0.1348, 0.30636, 0.65711, 0.30636, 0.1348, 0.064, 0.028, 0.01, 0.003, 0.0006 },
    { 0.0, 0.00166, 0.00726, 0.02369, 0.06055, 0.1353, 0.3028, 0.64626, 0.3028, 0.1353, 0.06055, 0.02369, 0.00726, 0.00166, 0.0 },
    { 0.0, 0.0, 0.00426, 0.017, 0.052, 0.13326, 0.324532, 0.63592, 0.324532, 0.13326, 0.052, 0.017, 0.00426, 0.0, 0.0 },
    { 0.0, 0.0, 0.0, 0.00514, 0.022, 0.09, 0.2956, 0.60248, 0.2956, 0.09, 0.022, 0.00514, 0.0, 0.0, 0.0 },
    { 0.0, 0.0, 0.0, 0.0, 0.0053, 0.0528, 0.2503, 0.57293, 0.2503, 0.0528, 0.0053, 0.0, 0.0, 0.0, 0.0 },
    { 0.0, 0.0, 0.0, 0.0, 0.0, 0.04567, 0.18454, 0.51596, 0.18454, 0.04567, 0.0, 0.0, 0.0, 0.0, 0.0 }};
static const uint KERNEL_TAPS[6] = { 15u, 13u, 11u, 9u, 7u, 5u };

// Where a cell is in the region, x and z from 0 to 1.
float2 unit_of(Mirai_Vfx_Cell cell) {
    Mirai_Vfx_Grid g = mirai_vfx_grid(cell.ctx, fluid);
    return (float2(cell.index.xz - g.first.xz) + 0.5) / float2(max(g.cells.xz, int2(1)));
}

// 1 inside the region, falling to 0 over width of it at its edges.
float edge_mask(float width, float power, float2 unit) {
    float w = 1.0 / max(width, 0.001);
    float2 v = unit * 2.0 * w;
    float d = max(abs(v.x - w), abs(v.y - w));
    return pow(saturate((w - 0.01) - d), max(power, 0.01));
}

// A layer of the fluid offset cells away from a cell, along x and z, between cells.
float4 near(Mirai_Vfx_Cell cell, float2 offset, uint layer) {
    float size = mirai_vfx_grid(cell.ctx, fluid).cell_size;
    return mirai_vfx_grid_sample(cell.ctx, fluid, cell.position + float3(offset.x, 0.0, offset.y) * size, layer);
}

// How far a point is from the segment from a to b.
float segment_distance(float2 u, float2 a, float2 b) {
    float2 ua = u - a, ba = b - a;
    float h = saturate(dot(ua, ba) / max(dot(ba, ba), 1e-12));
    return length(ua - ba * h);
}

void initialize(Mirai_Vfx_Context ctx, Parameters p, inout Mirai_Vfx_Particle particle, inout Attributes a) {}

// How much of a cell an obstacle takes: 1 inside a closed mesh or on a surface
// of the scene, falling to 0 at the reach. Rays along x and z from the middle
// of the cell; the one along +x crosses the region, to tell the inside of
// what is wider than the reach.
float obstacle_at(Mirai_Vfx_Cell cell, Parameters p) {
    if (!(p.obstacle_reach > 0.0)) return 0.0;
    Mirai_Vfx_Grid g = mirai_vfx_grid(cell.ctx, fluid);
    float across = float(max(g.cells.x, g.cells.z)) * g.cell_size;
    float nearest = p.obstacle_reach;
    for (uint side = 0u; side < 4u; side++) {
        float3 direction = side == 0u ? float3(1.0, 0.0, 0.0) : side == 1u ? float3(-1.0, 0.0, 0.0) : side == 2u ? float3(0.0, 0.0, 1.0) : float3(0.0, 0.0, -1.0);
        Mirai_Vfx_Hit h = mirai_vfx_trace(cell.ctx, cell.position, direction, side == 0u ? max(across, p.obstacle_reach) : p.obstacle_reach);
        if (!h.hit) continue;
        if (h.inside) return 1.0;
        nearest = min(nearest, h.distance);
    }
    return 1.0 - smoothstep(0.0, p.obstacle_reach, nearest);
}

// The height of the ground over the plane at a cell: the first surface a ray
// down from ground_reach above meets, terrain, foliage or a mesh; down to
// -ground_reach without one, and ground_reach inside a closed mesh.
float ground_at(Mirai_Vfx_Cell cell, Parameters p) {
    if (!(p.ground_reach > 0.0)) return 0.0;
    Mirai_Vfx_Hit h = mirai_vfx_trace(cell.ctx, cell.position + float3(0.0, p.ground_reach, 0.0), float3(0.0, -1.0, 0.0), 2.0 * p.ground_reach);
    if (!h.hit) return -p.ground_reach;
    return h.inside ? p.ground_reach : p.ground_reach - h.distance;
}

void paint(Mirai_Vfx_Cell cell, Parameters p) {
    float size = mirai_vfx_grid(cell.ctx, fluid).cell_size;
    float dt = cell.ctx.delta_time;
    float4 stroke = float4(0.0);
    uint count = mirai_vfx_channel_count(cell.ctx, brushes);
    for (uint i = 0u; i < count; i++) {
        Mirai_Vfx_Birth b = mirai_vfx_channel_birth(cell.ctx, brushes, i);
        if (b.values.z > 1.5) continue;
        float radius = max(b.size * p.brush_size, 1e-4);
        bool span = b.values.z > 0.5;
        float2 now = b.position.xz, before = now - b.velocity.xz * dt;
        if (span) { before = b.position.xz; now = before + b.velocity.xz; }
        float shape = 1.0 - smoothstep(saturate(p.brush_hardness) * radius, radius, segment_distance(cell.position.xz, before, now));
        if (!(shape > 0.0)) continue;
        float2 along = now - before;
        float2 flow = span ? (dot(along, along) > 1e-12 ? normalize(along) * b.values.y : float2(0.0)) : b.velocity.xz * p.brush_velocity;
        stroke.xy += flow * (dt / size) * shape;
        stroke.z += b.values.x * p.brush_strength * shape;
        stroke.w = max(stroke.w, shape);
    }
    mirai_vfx_grid_store(cell, 3u, float4(stroke.xy, saturate(stroke.z), stroke.w));
    float4 held = mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 2u);
    float ground = ground_at(cell, p);
    float peak = p.peak_height > 0.0 ? saturate(ground / p.peak_height) : 0.0;
    mirai_vfx_grid_store(cell, 2u, float4(held.xy, max(obstacle_at(cell, p), peak), ground));
}

// What the fluid has where each probe of the brushes is, nothing out of its
// region, appended to fluid_samples by the first cell of the region in the
// steps that have probes: the id of the probe in three
// floats of 22, 22 and 20 bits, its density, its flow in metres a second along
// x and z, its wetness and the height of the ground under it.
void fluid_probe(Mirai_Vfx_Cell cell, Parameters p) {
    Mirai_Vfx_Grid g = mirai_vfx_grid(cell.ctx, fluid);
    if (any(cell.index != g.first)) return;
    uint count = mirai_vfx_channel_count(cell.ctx, brushes);
    float speed = cell.ctx.delta_time > 0.0 ? p.sim_speed * g.cell_size / cell.ctx.delta_time : 0.0;
    for (uint i = 0u; i < count; i++) {
        Mirai_Vfx_Birth b = mirai_vfx_channel_birth(cell.ctx, brushes, i);
        if (!(b.values.z > 1.5)) continue;
        float4 here = mirai_vfx_grid_sample(cell.ctx, fluid, b.position, 0u);
        float ground = mirai_vfx_grid_sample(cell.ctx, fluid, b.position, 2u).w;
        uint entry;
        if (!mirai_vfx_data_append(cell.ctx, fluid_samples, entry)) return;
        float words[8] = { b.values.x, b.values.y, b.values.w, here.z, here.x * speed, here.y * speed, here.w, ground };
        for (uint w = 0u; w < 8u; w++) mirai_vfx_data_store(cell.ctx, fluid_samples, entry, w, asuint(words[w]));
    }
}

void composite(Mirai_Vfx_Cell cell, Parameters p) {
    fluid_probe(cell, p);
    float2 unit = unit_of(cell);
    float s = p.sim_speed;
    float4 carried = mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 1u);
    float2 gradient = 0.5 * float2(near(cell, float2(s, 0.0), 2u).x - near(cell, float2(-s, 0.0), 2u).x, near(cell, float2(0.0, s), 2u).x - near(cell, float2(0.0, -s), 2u).x);
    float2 velocity = carried.xy - gradient;
    // Downhill: the slope of the ground, metres a metre, over the cells around.
    if (p.ground_reach > 0.0 && p.downhill > 0.0) {
        float size = mirai_vfx_grid(cell.ctx, fluid).cell_size;
        float2 slope = float2(near(cell, float2(s, 0.0), 2u).w - near(cell, float2(-s, 0.0), 2u).w, near(cell, float2(0.0, s), 2u).w - near(cell, float2(0.0, -s), 2u).w) / max(2.0 * s * size, 1e-6);
        velocity -= p.downhill * slope;
    }
    float4 painted = mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 3u);
    float edge = edge_mask(p.edge_width, p.edge_pow, unit);
    // Density: what was carried, less what the eraser takes, with what the brushes add.
    float density = saturate(carried.z - min(p.eraser, painted.z) + (1.0 - p.eraser) * painted.z);
    density *= (p.density_feedback * 0.5 * max(edge, 0.7) + 0.5) * edge;
    // The brushes push where they paint; elsewhere the wind, by the density.
    float2 brush = painted.xy;
    float2 pushed = brush + (1.0 - saturate(dot(brush, brush))) * p.wind;
    velocity += 0.5 * (carried.z + p.eraser * 0.1 * painted.z) * pushed;
    // An obstacle stops the fluid in it, but for what it lets through.
    float open = clamp(1.0 - mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 2u).z, p.obstacle_weaken, 1.0);
    velocity = clamp(velocity, -p.velocity_clamp, p.velocity_clamp) * open;
    density *= open;
    float wet = mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 0u).w * 0.982 + max(density, 1e-6) * (1.0 - p.wet_feedback);
    mirai_vfx_grid_store(cell, 0u, float4(velocity, density, saturate(wet) * edge_mask(p.edge_width, 1.0, unit)));
}

void advect(Mirai_Vfx_Cell cell, Parameters p) {
    float4 fluid_here = mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 0u);
    float4 from = near(cell, -fluid_here.xy * p.sim_speed, 0u);
    mirai_vfx_grid_store(cell, 1u, float4(from.xyz * p.velocity_feedback, 0.0));
}

void diverge(Mirai_Vfx_Cell cell, Parameters p) {
    float s = p.sim_speed;
    float across = near(cell, float2(s, 0.0), 1u).x - near(cell, float2(-s, 0.0), 1u).x;
    float along = near(cell, float2(0.0, s), 1u).y - near(cell, float2(0.0, -s), 1u).y;
    float punctured = p.puncture * 0.01 * mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 3u).z;
    float divergence = clamp(p.divergence_mult * (punctured + across + along), -2.0, 2.0);
    float4 held = mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 2u);
    mirai_vfx_grid_store(cell, 2u, float4(held.x, divergence, held.zw));
}

// The pressure: the first iteration spreads pressure and divergence across x
// with their kernels, the second along z, and takes the divergence from the
// pressure.
void pressure(Mirai_Vfx_Cell cell, Parameters p) {
    uint kernel = uint(ceil((15.0 - clamp(15.0 * p.kernel_mult, 5.0, 15.0)) * 0.5));
    int offset = clamp(int(round(p.kernel_offset)), -int(kernel), 5 - int(kernel));
    uint taps = KERNEL_TAPS[kernel];
    float2 direction = cell.ctx.iteration == 0u ? float2(p.sim_speed, 0.0) : float2(0.0, p.sim_speed);
    float2 start = -direction * (float(taps - 1u) * 0.5);
    float2 sum = float2(0.0);
    for (uint i = 0u; i < taps; i++) {
        float2 value = near(cell, start + direction * float(i), 2u).xy;
        sum += value * float2(GAUSS_KERNELS[uint(int(kernel) + offset)][i + kernel], DIVERGENCE_KERNELS[kernel][i + kernel]);
    }
    float2 spread = cell.ctx.iteration == 0u ? sum : float2(sum.x - sum.y, sum.y);
    mirai_vfx_grid_store(cell, 2u, float4(spread * 0.999 * float2(p.pressure_feedback, p.divergence_feedback), mirai_vfx_grid_load(cell.ctx, fluid, cell.index, 2u).zw));
}

// Smooth noise from 0 to 1 over a lattice of the world.
float lattice_hash(int3 c) {
    uint h = uint(c.x) * 73856093u ^ uint(c.y) * 19349663u ^ uint(c.z) * 83492791u;
    h = (h ^ (h >> 13u)) * 1274126177u;
    return float(h >> 8u) / 16777216.0;
}
float value_noise(float3 u) {
    int3 c = int3(floor(u));
    float3 f = u - floor(u);
    f = f * f * (3.0 - 2.0 * f);
    float sum = 0.0;
    for (uint corner = 0u; corner < 8u; corner++) {
        int3 side = int3(int(corner & 1u), int((corner >> 1u) & 1u), int(corner >> 2u));
        float3 w = lerp(1.0 - f, f, float3(side));
        sum += w.x * w.y * w.z * lattice_hash(c + side);
    }
    return sum;
}

// The fluid as a medium in the grid volume, as FluidNinja extrudes it into a
// heterogeneous volume: its density is an elevation over the plane of the
// fluid, a column that rises volume_height a unit of density (volume_below of
// that under the plane), thins out towards its top and widens volume_spread a
// metre up. Noise over the cells of the world, rising slowly, takes
// volume_noise of it away in blots; its glow is its density by volume_glow.
void extrude(Mirai_Vfx_Cell cell, Parameters p) {
    Mirai_Vfx_Grid g = mirai_vfx_grid(cell.ctx, fluid);
    float density = 0.0;
    if (g.valid && p.volume_height > 0.0) {
        float height = cell.position.y - (g.corner.y + 0.5 * g.cell_size);
        float reach = height >= 0.0 ? p.volume_height : p.volume_height * p.volume_below;
        float wide = abs(height) * p.volume_spread;
        float spread = mirai_vfx_grid_sample(cell.ctx, fluid, cell.position, 0u).z;
        if (wide > 0.5 * g.cell_size) {
            for (uint side = 0u; side < 4u; side++) {
                float2 d = side == 0u ? float2(1.0, 0.0) : side == 1u ? float2(-1.0, 0.0) : side == 2u ? float2(0.0, 1.0) : float2(0.0, -1.0);
                spread += mirai_vfx_grid_sample(cell.ctx, fluid, cell.position + float3(d.x, 0.0, d.y) * wide, 0u).z;
            }
            spread *= 0.2;
        }
        float column = reach * spread;
        if (column > 1e-4) density = spread * (1.0 - smoothstep(0.0, column, abs(height)));
        if (density > 0.0 && p.volume_noise > 0.0) {
            float size = mirai_vfx_grid(cell.ctx, volume).cell_size;
            float3 u = (float3(cell.index) + 0.5) * size / p.volume_noise_size;
            density *= 1.0 - p.volume_noise * value_noise(u - float3(0.0, 0.3 * cell.ctx.time / p.volume_noise_size, 0.0));
        }
    }
    mirai_vfx_grid_store(cell, 0u, float4(density, density * p.volume_glow, 0.0, 0.0));
}

void update(Mirai_Vfx_Context ctx, Parameters p, inout Mirai_Vfx_Particle particle, inout Attributes a) {}

void render(Mirai_Vfx_Context ctx, Parameters p, Mirai_Vfx_Particle particle, Attributes a, inout Mirai_Vfx_Visual visual) {}
}
