package fluids

import "mirai:core"
import mm "mirai:std/math"
import vfx "plugins:vfx/runtime"

// Fluids on a plane: velocity, density, pressure and wetness in the cells of
// a grid of the vfx plugin flat along y, solved by the stages of the Vfx
// program Fluid (shaders/fluid.slang, after the core of FluidNinja Live 2.0).
// A fluid is an entity with a Particle_Grid of four layers and a
// Particle_Emitter whose effect runs Fluid, with a silent Particle_Channel
// CHANNEL_BRUSHES that hands its program the brushes and the spans of the
// splines. Particles of the program Fluid_Drift follow its flow. What
// paints into the fluids are the entities with a Fluid_Brush or a
// Fluid_Spline.

// The channels of the fluids: their programs read them by these names
// (`//! resource brushes channel`).
CHANNEL_BRUSHES :: vfx.Particle_Channel_Name(1)
CHANNEL_DISPLACERS :: vfx.Particle_Channel_Name(2)

// The name of the grid of a fluid made in the editor, which Fluid_Ground
// (shaders/fluid_ground.slang) reads.
GRID :: "fluid"

// A brush that paints into the fluids where its entity is: a disc that
// sweeps from where it was the tick before, adding density and the flow of
// its motion.
@(component,description="Paints into the fluids of the world where it is: density and the flow of its motion.")
Fluid_Brush :: struct {
    radius:f32 `mirai:"min=0,unit=m"`,
    density:f32 `mirai:"min=0"`,       // what it adds at its middle, multiplied by the strength of the fluid
    follow:f32 `mirai:"min=0"`,        // share of its motion it gives the fluid
    push:[3]f32 `mirai:"unit=m/s"`,    // a flow of its own, in the world
}

FLUID_BRUSH_DEFAULT :: Fluid_Brush{radius=0.5,density=1,follow=1}

FLUID_SPLINE_POINTS :: 16
FLUID_SPLINE_STEPS :: 4 // straight pieces of a span between two points

// A curve through points of its entity, the Catmull-Rom curve of std/math,
// along which the fluids flow, as FluidNinja's spline to velocity field: a
// band as wide as width where the fluid flows along the curve at speed, and
// takes density.
@(component,description="Drives the fluids along a curve through its points: a band where they flow at a speed and take density.")
Fluid_Spline :: struct {
    points:[FLUID_SPLINE_POINTS][3]f32 `mirai:"unit=m"`, // in the space of the entity
    count:u32 `mirai:"max=16"`,                         // of points the curve passes through
    width:f32 `mirai:"min=0,unit=m"`,
    speed:f32 `mirai:"unit=m/s"`,
    density:f32 `mirai:"min=0"`,                         // what it adds at its middle, multiplied by the strength of the fluid
}

FLUID_SPLINE_DEFAULT :: Fluid_Spline{points={0={0,0,0},1={2,0,0},2={4,0,1}},count=3,width=0.5,speed=2}

// A span of a spline as the program reads it among the brushes of the
// channel: from position along velocity (not a velocity: the span itself).
FLUID_SPAN :: 1

// The brushes of the world to the channel of the fluids, every tick: where
// each is, how fast it went since the tick before and what it gives. Without
// playing (the editor) they paint every frame, as the preview of the
// emitters runs.
@(step="fixed",loops="game editor",stage="end",after="transforms_propagate")
fluid_brushes :: proc(brushes:core.Read(Fluid_Brush),worlds:core.Read(core.World_Transform),channels:^vfx.Particle_Channels,time:core.Time,frame:core.Frame_Time) {
    dt:=time.dt if time.playing else frame.dt
    if !(dt>0) {return}
    for row in 0..<core.count(brushes) {
        e:=core.entity_at(brushes,row)
        brush:=core.at(brushes,row)
        world,placed:=core.get(worlds,e)
        if !placed {continue}
        moved:=(world.transform.position-world.previous.position)/dt
        vfx.channel_emit(channels,CHANNEL_BRUSHES,vfx.Channel_Birth{
            position=world.transform.position,velocity=moved*brush.follow+brush.push,
            size=max(brush.radius,0),count=1,values={brush.density,0,0,0},
        })
    }
}

// The splines of the world to the channel of the fluids, as the brushes go:
// each span of each, in straight pieces along the curve.
@(step="fixed",loops="game editor",stage="end",after="transforms_propagate")
fluid_splines :: proc(splines:core.Read(Fluid_Spline),worlds:core.Read(core.World_Transform),channels:^vfx.Particle_Channels) {
    for row in 0..<core.count(splines) {
        e:=core.entity_at(splines,row)
        spline:=core.at(splines,row)
        world,placed:=core.get(worlds,e)
        count:=int(min(spline.count,FLUID_SPLINE_POINTS))
        if !placed || count<2 {continue}
        points:[FLUID_SPLINE_POINTS][3]f32
        for i in 0..<count {points[i]=mm.transform_point(world.transform,spline.points[i])}
        for span in 0..<count-1 {
            p0,p1,p2,p3:=points[max(span-1,0)],points[span],points[span+1],points[min(span+2,count-1)]
            from:=p1
            for step in 1..=FLUID_SPLINE_STEPS {
                to:=mm.catmull_rom(p0,p1,p2,p3,f32(step)/FLUID_SPLINE_STEPS)
                vfx.channel_emit(channels,CHANNEL_BRUSHES,vfx.Channel_Birth{
                    position=from,velocity=to-from,size=max(spline.width,0)*0.5,count=1,
                    values={spline.density,spline.speed,FLUID_SPAN,0},
                })
                from=to
            }
        }
    }
}

// The waves of a surface of water (the Vfx program Water_Waves, shaders/
// water_waves.slang): an entity with a Particle_Grid flat along y of two
// layers that follows the view, a Particle_Emitter whose effect runs
// Water_Waves and a silent Particle_Channel CHANNEL_DISPLACERS. A
// Particle_World_Texture of layer 1 gives the material of the water its
// normals and foam. What presses the waves are the entities with a
// Water_Displacer.
WAVE_GRID :: "waves" // the name of its grid and of the texture of the world the materials read

// What a body displaces of the water around it, for the waves: the volume
// of it under the surface now and how wide the disc of the surface it sinks
// is; it moves as its entity moves, which leaves a wake. Whoever knows the
// submerged volume writes it (the water of the physics plugin, or a game);
// zero presses nothing.
@(component,description="Presses the waves of the water: its submerged volume over a disc of the surface, moving as its entity moves.")
Water_Displacer :: struct {
    radius:f32 `mirai:"min=0,unit=m"`,
    volume:f32 `mirai:"min=0,unit=m³"`, // under the surface now
}

WATER_DISPLACER_DEFAULT :: Water_Displacer{radius=0.5,volume=0.1}

// The bodies that displace water to the channel of the waves, every tick, as
// the brushes go: where each is, how fast it went since the tick before, its
// radius and its submerged volume.
@(step="fixed",loops="game editor",stage="end",after="transforms_propagate")
water_displacers :: proc(displacers:core.Read(Water_Displacer),worlds:core.Read(core.World_Transform),channels:^vfx.Particle_Channels,time:core.Time,frame:core.Frame_Time) {
    dt:=time.dt if time.playing else frame.dt
    if !(dt>0) {return}
    for row in 0..<core.count(displacers) {
        e:=core.entity_at(displacers,row)
        displacer:=core.at(displacers,row)
        world,placed:=core.get(worlds,e)
        if !placed || !(displacer.volume>0) {continue}
        vfx.channel_emit(channels,CHANNEL_DISPLACERS,vfx.Channel_Birth{
            position=world.transform.position,velocity=(world.transform.position-world.previous.position)/dt,
            size=max(displacer.radius,0),count=1,values={displacer.volume,0,0,0},
        })
    }
}

// A probe among the brushes of the channel (values.z): it paints nothing; the
// fluid it is in tells where it is.
FLUID_PROBE :: 2

// The data channel the fluids append what they have where the probes are,
// FLUID_SAMPLE_WORDS words an entry (shaders/fluid.slang fluid_probe).
FLUID_SAMPLES :: "fluid_samples"
FLUID_SAMPLE_WORDS :: 8

// What the fluids have where its entity is comes back to the game, frames
// later, in Fluid_Samples: for presentation (leaves that drift, a sound, a
// wet footprint), as the reports of particles are.
@(component,description="Reads the fluids where it is: their density, flow and wetness come back frames later, for presentation.")
Fluid_Probe :: struct {}

// What a fluid had where a probe was, as the GPU left it frames before.
Fluid_Sample :: struct {
    entity:core.Entity,
    density:f32,
    velocity:[3]f32 `mirai:"unit=m/s"`, // along the plane of the fluid
    wet:f32,
    ground:f32 `mirai:"unit=m"`,        // the height of the ground over the plane, with ground_reach
}

// The samples of the probes of the last frame with ticks that came back from
// the GPU; a probe out of every fluid has nothing in them, and one in a world
// without fluids, no sample. It is presentation alone: no function of
// fixed reads it, and nothing of the game is decided by it.
@(storage,host,by_world,presentation,free="fluid_samples_free")
Fluid_Samples :: struct {
    samples:[dynamic]Fluid_Sample,
}

fluid_samples_free :: proc(samples:^Fluid_Samples) {
    delete(samples.samples)
    samples^={}
}

// What the fluids had where the probe e was; false while nothing came back.
fluid_sample :: proc(samples:^Fluid_Samples,e:core.Entity) -> (Fluid_Sample,bool) {
    if samples==nil {return {},false}
    for sample in samples.samples {
        if sample.entity==e {return sample,true}
    }
    return {},false
}

// The id of an entity as three floats of whole numbers (of 22, 22 and 20
// bits), which the GPU keeps as they are; and back.
@(private)
probe_id :: proc "contextless" (e:core.Entity) -> (id:[3]f32) {
    bits:=u64(e)
    return {f32(bits&(1<<22-1)),f32((bits>>22)&(1<<22-1)),f32(bits>>44)}
}

@(private)
probe_entity :: proc "contextless" (id:[3]f32) -> core.Entity {
    return core.Entity(u64(id.x)|u64(id.y)<<22|u64(id.z)<<44)
}

// The probes of the world to the channel of the fluids, as the brushes go.
@(step="fixed",loops="game editor",stage="end",after="transforms_propagate")
fluid_probes :: proc(probes:core.Read(Fluid_Probe),worlds:core.Read(core.World_Transform),channels:^vfx.Particle_Channels) {
    for row in 0..<core.count(probes) {
        e:=core.entity_at(probes,row)
        world,placed:=core.get(worlds,e)
        if !placed {continue}
        id:=probe_id(e)
        vfx.channel_emit(channels,CHANNEL_BRUSHES,vfx.Channel_Birth{position=world.transform.position,count=1,values={id.x,id.y,FLUID_PROBE,id.z}})
    }
}

// What came back of the probes: the samples of the frame, and the channel watched for
// the next while there are probes. Of a probe in two fluids, the densest.
@(step="render",loops="game editor",before="particles_sync")
fluid_samples_read :: proc(probes:core.Read(Fluid_Probe),watch:^vfx.Particle_Data_Watch,read:core.Ref(vfx.Particle_Data_Read),samples:^Fluid_Samples) {
    if samples==nil {return}
    if core.count(probes)==0 {
        clear(&samples.samples)
        return
    }
    if watch!=nil {vfx.data_watch(watch,FLUID_SAMPLES)}
    // A frame without ticks gives the fluids no probes: the samples stay.
    entries,words:=vfx.data_entries(read.ptr,FLUID_SAMPLES)
    if words<FLUID_SAMPLE_WORDS || len(entries)==0 {return}
    clear(&samples.samples)
    for at:=0;at+words<=len(entries);at+=words {
        w:=entries[at:][:FLUID_SAMPLE_WORDS]
        sample:=Fluid_Sample{entity=probe_entity({w[0],w[1],w[2]}),density=w[3],velocity={w[4],0,w[5]},wet=w[6],ground=w[7]}
        if core.row_of(probes,sample.entity)<0 {continue}
        kept:=false
        for &other in samples.samples {
            if other.entity!=sample.entity {continue}
            if sample.density>other.density {other=sample}
            kept=true
        }
        if !kept {append(&samples.samples,sample)}
    }
}
