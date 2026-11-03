package fluids

import "core:testing"
import "mirai:core"
import "mirai:std/base"
import mm "mirai:std/math"
import vfx "plugins:vfx/runtime"

// A brush gives the channel of the fluids where it is, how fast it moved
// since the tick before with its own flow, its radius and its density; one
// without a place gives nothing, and neither does a world that does not move
// on.
@(test)
brushes_paint_where_they_are_with_the_flow_of_their_motion :: proc(t: ^testing.T) {
	entities: core.Entities
	core.entities_init(&entities)
	defer core.entities_destroy(&entities)
	brushes: core.Table(Fluid_Brush)
	worlds: core.Table(core.World_Transform)
	core.table_init(&brushes, "Fluid_Brush");core.table_init(&worlds, "World_Transform")
	defer {core.table_destroy(&brushes);core.table_destroy(&worlds)}
	channels: vfx.Particle_Channels
	defer core.value_free(&channels, type_info_of(vfx.Particle_Channels))
	moving := core.create(&entities)
	before, now := mm.TRANSFORM_IDENTITY, mm.TRANSFORM_IDENTITY
	before.position, now.position = {1, 0, 2}, {1.5, 0, 2}
	core.add(&brushes, moving, Fluid_Brush{radius = 0.4, density = 2, follow = 1, push = {0, 0, 3}})
	core.add(&worlds, moving, core.World_Transform{now, before})
	unplaced := core.create(&entities)
	core.add(&brushes, unplaced, FLUID_BRUSH_DEFAULT)
	core.table_settle(&brushes, &entities);core.table_settle(&worlds, &entities);core.entities_settle(&entities)
	DT :: f32(0.25)
	fluid_brushes(core.read(&brushes), core.read(&worlds), &channels, {playing = true, dt = DT}, {})
	fluid_brushes(core.read(&brushes), core.read(&worlds), &channels, {playing = true}, {})
	pushed := channels.queue.items[:]
	if !testing.expect_value(t, len(pushed), 1) {return}
	testing.expect_value(t, pushed[0].channel, CHANNEL_BRUSHES)
	b := pushed[0].birth
	testing.expect(t, b.position == now.position && b.velocity == {2, 0, 3} && b.size == 0.4 && b.values.x == 2 && b.count == 1, "the brush paints where it is, with its motion and its flow")
}

// A spline gives the channel each of its spans in pieces that run through
// its points, placed by its entity, with half its width, its speed and its
// density; the pieces follow on from each other.
@(test)
splines_drive_the_fluids_along_their_spans :: proc(t: ^testing.T) {
	entities: core.Entities
	core.entities_init(&entities)
	defer core.entities_destroy(&entities)
	splines: core.Table(Fluid_Spline)
	worlds: core.Table(core.World_Transform)
	core.table_init(&splines, "Fluid_Spline");core.table_init(&worlds, "World_Transform")
	defer {core.table_destroy(&splines);core.table_destroy(&worlds)}
	channels: vfx.Particle_Channels
	defer core.value_free(&channels, type_info_of(vfx.Particle_Channels))
	e := core.create(&entities)
	placed := mm.TRANSFORM_IDENTITY
	placed.position = {10, 0, 0}
	core.add(&splines, e, Fluid_Spline{points = {0 = {0, 0, 0}, 1 = {2, 0, 0}, 2 = {4, 0, 2}}, count = 3, width = 1, speed = 3, density = 0.5})
	core.add(&worlds, e, core.World_Transform{placed, placed})
	core.table_settle(&splines, &entities);core.table_settle(&worlds, &entities);core.entities_settle(&entities)
	fluid_splines(core.read(&splines), core.read(&worlds), &channels)
	pushed := channels.queue.items[:]
	if !testing.expect_value(t, len(pushed), 2 * FLUID_SPLINE_STEPS) {return}
	first, last := pushed[0].birth, pushed[len(pushed) - 1].birth
	testing.expect(t, first.position == {10, 0, 0} && first.size == 0.5 && first.values == {0.5, 3, FLUID_SPAN, 0}, "the first piece starts at the first point, placed")
	testing.expectf(t, abs(last.position.x + last.velocity.x - 14) < 1e-4 && abs(last.position.z + last.velocity.z - 2) < 1e-4, "the last piece ends at the last point: %v", last.position + last.velocity)
	for i in 1 ..< len(pushed) {
		end := pushed[i - 1].birth.position + pushed[i - 1].birth.velocity
		testing.expect(t, abs(end.x - pushed[i].birth.position.x) < 1e-4 && abs(end.z - pushed[i].birth.position.z) < 1e-4, "each piece starts where the one before ends")
	}
}

// A body under water gives the channel of the waves where it is, how fast
// it moved, its radius and its submerged volume; one with none gives nothing.
@(test)
displacers_press_the_waves_where_they_are :: proc(t: ^testing.T) {
	entities: core.Entities
	core.entities_init(&entities)
	defer core.entities_destroy(&entities)
	displacers: core.Table(Water_Displacer)
	worlds: core.Table(core.World_Transform)
	core.table_init(&displacers, "Water_Displacer");core.table_init(&worlds, "World_Transform")
	defer {core.table_destroy(&displacers);core.table_destroy(&worlds)}
	channels: vfx.Particle_Channels
	defer core.value_free(&channels, type_info_of(vfx.Particle_Channels))
	boat := core.create(&entities)
	before, now := mm.TRANSFORM_IDENTITY, mm.TRANSFORM_IDENTITY
	before.position, now.position = {0, 0, 0}, {0, 0, 1}
	core.add(&displacers, boat, Water_Displacer{radius = 1.5, volume = 2})
	core.add(&worlds, boat, core.World_Transform{now, before})
	dry := core.create(&entities)
	core.add(&displacers, dry, Water_Displacer{radius = 1})
	core.add(&worlds, dry, core.World_Transform{now, now})
	core.table_settle(&displacers, &entities);core.table_settle(&worlds, &entities);core.entities_settle(&entities)
	water_displacers(core.read(&displacers), core.read(&worlds), &channels, {playing = true, dt = 0.5}, {})
	pushed := channels.queue.items[:]
	if !testing.expect_value(t, len(pushed), 1) {return}
	testing.expect_value(t, pushed[0].channel, CHANNEL_DISPLACERS)
	b := pushed[0].birth
	testing.expect(t, b.position == {0, 0, 1} && b.velocity == {0, 0, 2} && b.size == 1.5 && b.values.x == 2, "the body presses where it is, with its motion and its volume")
}

// A probe gives the channel of the fluids where it is and its id, and paints
// nothing; what the fluids append for it comes back by its entity, the densest
// of two fluids, and a frame with nothing back keeps what came before.
@(test)
probes_read_the_fluids_where_they_are :: proc(t: ^testing.T) {
	entities: core.Entities
	core.entities_init(&entities)
	defer core.entities_destroy(&entities)
	probes: core.Table(Fluid_Probe)
	worlds: core.Table(core.World_Transform)
	core.table_init(&probes, "Fluid_Probe");core.table_init(&worlds, "World_Transform")
	defer {core.table_destroy(&probes);core.table_destroy(&worlds)}
	channels: vfx.Particle_Channels
	defer core.value_free(&channels, type_info_of(vfx.Particle_Channels))
	for _ in 0 ..< 1000 {core.create(&entities)}
	e := core.create(&entities)
	placed := mm.TRANSFORM_IDENTITY
	placed.position = {3, 0.5, -2}
	core.add(&probes, e, Fluid_Probe{})
	core.add(&worlds, e, core.World_Transform{placed, placed})
	core.table_settle(&probes, &entities);core.table_settle(&worlds, &entities);core.entities_settle(&entities)
	fluid_probes(core.read(&probes), core.read(&worlds), &channels)
	pushed := channels.queue.items[:]
	if !testing.expect_value(t, len(pushed), 1) {return}
	b := pushed[0].birth
	testing.expect(t, pushed[0].channel == CHANNEL_BRUSHES && b.position == placed.position && b.values.z == FLUID_PROBE, "the probe is where its entity is, among the brushes")
	testing.expect_value(t, probe_entity({b.values.x, b.values.y, b.values.w}), e)

	watch: vfx.Particle_Data_Watch
	defer core.value_free(&watch, type_info_of(vfx.Particle_Data_Watch))
	read: vfx.Particle_Data_Read
	defer vfx.particle_data_read_free(&read)
	samples: Fluid_Samples
	defer fluid_samples_free(&samples)
	id := probe_id(e)
	entry := vfx.Data_Read{name = base.name_hash(FLUID_SAMPLES), words = FLUID_SAMPLE_WORDS, fresh = true}
	append(&entry.entries, id.x, id.y, id.z, 0.25, 1, 2, 0.5, 0.1)
	append(&entry.entries, id.x, id.y, id.z, 0.75, -1, 0, 0.2, 0)
	append(&read.channels, entry)
	fluid_samples_read(core.read(&probes), &watch, core.ref(&read), &samples)
	testing.expect_value(t, len(watch.queue.items), 1)
	sample, found := fluid_sample(&samples, e)
	testing.expect(t, found && sample.density == 0.75 && sample.velocity == {-1, 0, 0} && sample.wet == 0.2, "the densest of the two fluids")
	// Nothing came back this frame: the sample stays.
	clear(&read.channels[0].entries)
	fluid_samples_read(core.read(&probes), &watch, core.ref(&read), &samples)
	_, found = fluid_sample(&samples, e)
	testing.expect(t, found, "a frame without ticks keeps the samples")
}
