#include "native.slang"
// The foam of the grid waves of fluids where the view meets a surface of the
// water before the scene, lit by the sun and the sky (water_fluids.foam_record,
// over water_over.vert). Radiance with its alpha; the second target is the
// share of the pixel it covers.
#define WATER_STAGE
#include "scene.slang"
#include "water.slang"
#include "fluid_waves.slang"
#include "depth.slang"

[[vk::binding(SLOT_PASS5, 0)]] Texture2D<float4> linear_depth : register(MIRAI_REGISTER(t, SLOT_PASS5), space0);

static const float3 FOAM_ALBEDO = float3(0.85, 0.88, 0.9);

struct Stage_Output {
    [[vk::location(0)]] float4 out_color : SV_Target0;
    [[vk::location(1)]] float4 out_coverage : SV_Target1;
};

[shader("fragment")]
Stage_Output main(float4 pixel_position : SV_Position) {
    Stage_Output output;
    int2 pixel = int2(pixel_position.xy);
    float2 uv = pixel_position.xy * frame.inv_resolution;
    float3 origin = view_origin(uv), ray = view_ray(uv);
    float near = frame.camera_position.w;
    float scene = linear_depth.Load(int3(pixel, 0)).r;
    float far = depth_empty(scene) ? 1e30 : depth_distance(scene);
    float4 color = float4(0.0);
    for (uint i = 0u; i < water.count; i++) {
        Water_Body b = bodies[i];
        if (b.surface.z > 0.5 || abs(ray.y) < 1e-6) continue;
        bool plane = b.surface.y > 0.5;
        // Where the view meets the surface: on the waves, from the still surface towards the height where it is.
        float top = b.surface.x;
        float t = (top - origin.y) / ray.y;
        for (int k = 0; plane && k < 2 && water_wave_count(b) > 0u; k++) {
            top = water_surface_at(b, (origin + ray * max(t, near)).xz);
            t = (top - origin.y) / ray.y;
        }
        if (!(t > near) || t >= far) continue;
        float3 hit = origin + ray * t;
        if (!plane && any(abs(transform_point(b.to_box, hit)) > 0.5)) continue;
        float foam = fluid_waves_at(hit).foam;
        if (!(foam > 0.01)) continue;
        float3 up = float3(0.0, 1.0, 0.0);
        float3 light = sky_irradiance(up);
        if (frame.sun_direction.w > 0.5) light += sun_light(hit) * saturate(frame.sun_direction.y);
        // Seen from under the water, less of the light reaches the eye through it.
        if (origin.y < top) light *= 0.35;
        float a = foam * 0.9;
        if (a > color.a) color = float4(FOAM_ALBEDO * light, a);
    }
    if (!(color.a > 0.0)) discard;
    output.out_color = float4(color.rgb, color.a);
    output.out_coverage = float4(color.a, 0.0, 0.0, 0.0);
    return output;
}
