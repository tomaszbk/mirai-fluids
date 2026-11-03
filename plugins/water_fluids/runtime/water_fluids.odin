package water_fluids

import "mirai:core"
import render "mirai:engine/render"
import "mirai:host"
import "mirai:std/base"
import fluids "project:plugins/fluids/runtime"
import phys "plugins:physics/runtime"
import vfx "plugins:vfx/runtime"
import water "plugins:water/runtime"

// The water and the waves of fluids: each body in the water presses the
// waves of the grid fluids.WAVE_GRID by what it has under the surface, which
// leaves a wake as it moves; the surface of the water bends with those waves
// (SURFACE_PROGRAM), and their foam goes over its glass where the view meets
// it before the scene.

SURFACE_PROGRAM :: "Water_Fluids_Surface" // shaders/water_fluids_surface.slang

// What a body presses the waves with: where it is, how it moves, the radius
// of the disc it sinks and the volume it has under the surface.
displacer_of :: proc "contextless" (body:phys.Fluid_Body) -> vfx.Channel_Birth {
    return {position={body.center.x,body.surface,body.center.z},velocity=body.velocity,size=clamp(body.reach,0.2,6),count=1,values={body.volume,0,0,0}}
}

@(step="fixed",loops="game editor",stage="simulate",after="physics_step")
water_fluids_displacers :: proc(physics:core.Ref(phys.Physics_State),channels:^vfx.Particle_Channels,time:core.Time) {
    if !time.playing || !(time.dt>0) {return}
    found:[water.WET_CAPACITY]phys.Fluid_Body
    count:=min(phys.fluid_bodies(physics,found[:]),len(found))
    for body in found[:count] {
        if body.volume>0 {vfx.channel_emit(channels,fluids.CHANNEL_DISPLACERS,displacer_of(body))}
    }
}

// The surface of the water takes SURFACE_PROGRAM where the project leaves
// the program of water.Water_Settings to water.
@(step="render",loops="game editor",before="water_render")
water_fluids_surface :: proc(settings:^water.Water_Settings) {
    if base.text_get(settings.surface_program[:])=="" {base.text_set(settings.surface_program[:],SURFACE_PROGRAM)}
}

@(storage,host)
Water_Fluids_Gpu :: struct {
    pipeline:render.Pipeline,
    water:^water.Water_Gpu, // of the frame being drawn; nil when it draws no foam
}

// The foam of the waves over the glass of the water, when the world has the
// texture of the waves.
@(step="render",loops="game editor",after="water_render",before="render_sync")
water_fluids_foam :: proc(state:^Water_Fluids_Gpu,gpu:core.Ref(water.Water_Gpu),grids:core.Read(vfx.Particle_Grid),textures:core.Read(vfx.Particle_World_Texture),app:^host.App) {
    state.water=nil
    if app.renderer==nil || gpu.ptr==nil || gpu.count==0 || !has_waves(grids,textures) {return}
    state.pipeline=render.stage_pipeline(app,{stage=.Blend,shader="water_over",fragment="water_fluids_foam",name="water foam",blend=.Alpha})
    if state.pipeline==0 {return}
    state.water=gpu.ptr
    render.frame_pass(app,.Blend,foam_record,state)
}

// Whether the world has the texture of the waves of fluids.
@(private)
has_waves :: proc(grids:core.Read(vfx.Particle_Grid),textures:core.Read(vfx.Particle_World_Texture)) -> bool {
    for row in 0..<core.count(textures) {
        grid,ok:=core.get(grids,core.entity_at(textures,row))
        if ok && base.text_equal(grid.name[:],fluids.WAVE_GRID) {return true}
    }
    return false
}

@(private)
foam_record :: proc(pass:^render.Pass,user:rawptr) {
    state:=cast(^Water_Fluids_Gpu)user
    if pass.glass==.Behind || state.water==nil {return}
    render.pass_blend_begin(pass,"water foam")
    render.pass_surface_read(pass,5,.Linear_Depth)
    render.pass_pipeline(pass,state.pipeline)
    if water.bodies_bind(pass,state.water) {render.pass_draw(pass,3)}
    render.pass_end(pass)
}
