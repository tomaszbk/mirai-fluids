package fluids_editor

import "core:fmt"
import "mirai:core"
import "mirai:editor"
import "mirai:editor/api"
import "mirai:host"
import "mirai:std/base"
import "mirai:std/serial"
import "mirai:ui"
import fluids "project:plugins/fluids/runtime"
import vfx "plugins:vfx/runtime"

// What the fluids plugin gives the editor: the cards of Create that make a
// fluid whole (its grid, its emitter of the effect Fluid and its channel of
// brushes), the medium it extrudes into, its brushes, splines and probes, and
// fluid.samples, what the probes read.

FLUID_COLOR :: ui.Color{90,170,240,255}

// plugins/fluids/assets/fluid.particle: the effect whose program is Fluid.
FLUID_EFFECT :: base.Asset_Id{0x666c7569645f6566,0x6665637400000001}

@(storage)
Fluid_Cards :: struct {provider:editor.Card_Provider}

fluid_cards_default :: proc() -> (cards:Fluid_Cards) {
    waves :: proc(y:f32) -> ui.Icon_Part {return ui.icon_part(.Line,{{-6.5,y},{-3.5,y-1.6},{-0.5,y},{2.5,y-1.6},{5.5,y}})}
    cards.provider.count=5
    cards.provider.cards[0]={label="Fluid",group="Effects",color=FLUID_COLOR,lift=0.02,make=fluid_make,drawing=ui.icon_drawing(waves(-2),waves(2.5))}
    cards.provider.cards[1]={label="Fluid volume",group="Effects",color=FLUID_COLOR,lift=1,make=volume_make,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{-5,5},{-5,-3},{0,-6},{5,-3},{5,5},{-5,5}}),waves(1))}
    cards.provider.cards[2]={label="Fluid brush",group="Effects",color=FLUID_COLOR,lift=0.3,component=fluids.Fluid_Brush,make=brush_make,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{-5,5},{0,-5},{5,5}}),waves(4))}
    cards.provider.cards[3]={label="Fluid spline",group="Effects",color=FLUID_COLOR,lift=0.3,component=fluids.Fluid_Spline,make=spline_make,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{-6,4},{-3,-2},{1,2},{4,-4},{6,-5}}))}
    cards.provider.cards[4]={label="Fluid probe",group="Effects",color=FLUID_COLOR,lift=0.3,component=fluids.Fluid_Probe,make=probe_make,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{0,-6},{0,3}}),ui.icon_part(.Line,{{-3,3},{3,3},{0,6},{-3,3}}))}
    return
}

// A name of grid no other of the world has: the name, or it with a number.
@(private)
grid_name_free :: proc(w:core.World_Ref,name:string) -> string {
    t:=core.world_table_of(w,vfx.Particle_Grid)
    taken :: proc(t:^core.Table(vfx.Particle_Grid),name:string) -> bool {
        if t==nil {return false}
        grids:=core.read(t)
        for row in 0..<core.count(grids) {
            grid:=core.at(grids,row)
            if base.text_get(grid.name[:])==name {return true}
        }
        return false
    }
    if !taken(t,name) {return name}
    for n:=2;;n+=1 {
        if candidate:=fmt.tprintf("%s_%d",name,n);!taken(t,candidate) {return candidate}
    }
}

// A fluid on a plane: a grid of four layers at the height of the entity, an
// emitter of the effect Fluid that goes over it, and its silent channel of brushes.
@(private)
fluid_make :: proc(s:^editor.Session,w:core.World_Ref,e:core.Entity) {
    grid:=vfx.Particle_Grid{cells={128,1,128},cell_size=0.0625,layers=4}
    base.text_set(grid.name[:],grid_name_free(w,fluids.GRID))
    if t:=core.world_table_of(w,vfx.Particle_Grid);t!=nil {core.add(t,e,grid)}
    if t:=core.world_table_of(w,vfx.Particle_Emitter);t!=nil {core.add(t,e,vfx.Particle_Emitter{particle=FLUID_EFFECT,active=true,loop=true,preview=true})}
    if t:=core.world_table_of(w,vfx.Particle_Channel);t!=nil {core.add(t,e,vfx.Particle_Channel{name=fluids.CHANNEL_BRUSHES,silent=true})}
}

// The medium a fluid extrudes into: a grid along x, y and z drawn as a
// volume. The fluids whose emitters bind nothing else to their resource
// volume extrude into the grid of the world named volume.
@(private)
volume_make :: proc(s:^editor.Session,w:core.World_Ref,e:core.Entity) {
    grid:=vfx.Particle_Grid{cells={64,24,64},cell_size=0.125,layers=1}
    base.text_set(grid.name[:],grid_name_free(w,"volume"))
    if t:=core.world_table_of(w,vfx.Particle_Grid);t!=nil {core.add(t,e,grid)}
    if t:=core.world_table_of(w,vfx.Particle_Volume);t!=nil {core.add(t,e,vfx.Particle_Volume{density=4,albedo={0.8,0.8,0.8},anisotropy=0.2})}
}

@(private)
brush_make :: proc(s:^editor.Session,w:core.World_Ref,e:core.Entity) {
    if t:=core.world_table_of(w,fluids.Fluid_Brush);t!=nil {core.add(t,e,fluids.FLUID_BRUSH_DEFAULT)}
}

@(private)
spline_make :: proc(s:^editor.Session,w:core.World_Ref,e:core.Entity) {
    if t:=core.world_table_of(w,fluids.Fluid_Spline);t!=nil {core.add(t,e,fluids.FLUID_SPLINE_DEFAULT)}
}

@(private)
probe_make :: proc(s:^editor.Session,w:core.World_Ref,e:core.Entity) {
    if t:=core.world_table_of(w,fluids.Fluid_Probe);t!=nil {core.add(t,e,fluids.Fluid_Probe{})}
}

@(storage)
Fluid_Api :: struct {provider:editor.Api_Provider}
FLUID_API_DEFAULT :: Fluid_Api{provider={register=api_register}}

@(private)
api_register :: proc(s:^editor.Session) {
    editor.api_method_register(s,{name="fluid.samples",summary="What the fluids of the world shown (the Play, or the document) had where each Fluid_Probe is, as the GPU left it a few frames ago: density, flow in m/s along the plane, wetness and the height of the ground. A probe out of every fluid reads zeros; one in no world with fluids, nothing.",flags={.Read_Only},run=api_samples})
}

@(private)
api_samples :: proc(s:^editor.Session,call:^api.Call) {
    w:=editor.shown_world(s)
    samples:=host.app_world_storage(s.app,w.data,fluids.Fluid_Samples)
    out:=call.out
    serial.write_u8(out,'{')
    api.write_key(out,"samples",true)
    serial.write_u8(out,'[')
    if samples!=nil {
        for sample,i in samples.samples {
            if i>0 {serial.write_u8(out,',')}
            serial.write_u8(out,'{')
            api.write_key(out,"id",true)
            api.write_id(out,editor.api_entity_id(w,sample.entity))
            api.write_key(out,"density");api.write_number(out,sample.density)
            api.write_numbers(out,"velocity",sample.velocity)
            api.write_key(out,"wet");api.write_number(out,sample.wet)
            api.write_key(out,"ground");api.write_number(out,sample.ground)
            serial.write_u8(out,'}')
        }
    }
    serial.write_u8(out,']')
    serial.write_u8(out,'}')
}
