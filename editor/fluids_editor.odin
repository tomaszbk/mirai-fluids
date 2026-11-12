package fluids_editor

import "mirai:editor"
import "mirai:editor/api"
import "mirai:host"
import "mirai:std/serial"
import "mirai:ui"
import fluids "project:plugins/fluids/runtime"

// What the fluids plugin gives the editor: the cards of Create that place
// the recipes of recipes/ (a fluid whole, with its grid, its emitter of the
// effect Fluid and its channel of brushes; the medium it extrudes into; its
// brushes, splines and probes), and fluid.samples, what the probes read.

FLUID_COLOR :: ui.Color{90,170,240,255}

@(storage)
Fluid_Cards :: struct {provider:editor.Card_Provider}

fluid_cards_default :: proc() -> (cards:Fluid_Cards) {
    waves :: proc(y:f32) -> ui.Icon_Part {return ui.icon_part(.Line,{{-6.5,y},{-3.5,y-1.6},{-0.5,y},{2.5,y-1.6},{5.5,y}})}
    cards.provider.count=5
    cards.provider.cards[0]={recipe="fluid",group="Effects",color=FLUID_COLOR,drawing=ui.icon_drawing(waves(-2),waves(2.5))}
    cards.provider.cards[1]={recipe="fluid_volume",group="Effects",color=FLUID_COLOR,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{-5,5},{-5,-3},{0,-6},{5,-3},{5,5},{-5,5}}),waves(1))}
    cards.provider.cards[2]={recipe="fluid_brush",group="Effects",color=FLUID_COLOR,component=fluids.Fluid_Brush,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{-5,5},{0,-5},{5,5}}),waves(4))}
    cards.provider.cards[3]={recipe="fluid_spline",group="Effects",color=FLUID_COLOR,component=fluids.Fluid_Spline,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{-6,4},{-3,-2},{1,2},{4,-4},{6,-5}}))}
    cards.provider.cards[4]={recipe="fluid_probe",group="Effects",color=FLUID_COLOR,component=fluids.Fluid_Probe,
        drawing=ui.icon_drawing(ui.icon_part(.Line,{{0,-6},{0,3}}),ui.icon_part(.Line,{{-3,3},{3,3},{0,6},{-3,3}}))}
    return
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
