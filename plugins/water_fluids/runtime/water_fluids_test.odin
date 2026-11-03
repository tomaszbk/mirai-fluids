package water_fluids

import "core:testing"
import phys "plugins:physics/runtime"

@(test)
a_body_presses_the_waves_by_its_volume_under_the_surface_where_it_floats :: proc(t:^testing.T) {
    floating:=phys.Fluid_Body{center={1,-0.2,2},velocity={0.5,0,0},volume=0.5,whole=1,surface=0.1,reach=0.9}
    pressed:=displacer_of(floating)
    testing.expect(t,pressed.values.x==0.5 && pressed.size==0.9 && pressed.velocity=={0.5,0,0})
    testing.expect_value(t,pressed.position,[3]f32{1,0.1,2})
}
