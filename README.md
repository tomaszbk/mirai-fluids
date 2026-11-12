# Mirai fluids

A plugin for the Mirai engine that simulates fluids on a plane: smoke, ink, water flowing over the
ground and the waves and wakes of a water surface. The solver runs on the GPU as the stages of a
Vfx program over a grid of the `vfx` plugin; the grid, its stages, the channels and the particles
are those of `vfx`, not another system.

Everything here is presentation: nothing of a fluid decides the game, enters a snapshot or a
rollback.

## Install

From the catalog, in the folder of a Mirai project:

```sh
mirai plugin add fluids
```

or from the Catalog of the Plugins page in the project settings of the editor. It depends on the
engine plugin `vfx`, which turns on with it.

The companion plugin in `plugins/` installs with it and turns on by itself when the project also
has the plugin it bridges:

- `water_fluids`: bodies in the water of the `water` plugin press the waves of the wave grid
  (`waves`) and leave wakes, the surface of the water bends with those waves and their foam is
  drawn over it ([below](#water-waves)).

## A fluid

An entity with (the Create card **Fluid** makes it whole, with the effect `assets/fluid.particle`):

- a `Particle_Grid` flat along y (cells along x and z) with four layers;
- a `Particle_Emitter` whose effect runs the Vfx program `Fluid` (`shaders/fluid.slang`), with its
  parameters (simulation speed, what it keeps each step, width of the pressure kernel, brushes,
  borders, wind);
- a silent `Particle_Channel` named `brushes` (`CHANNEL_BRUSHES`), through which the program reads
  the brushes without its effect starting particles. Brushes, splines and probes reach it as
  births of `core.Births` on that channel, so a game pushes its own the same way.

The layers of each cell, with velocities in cells per step:

| Layer | x | y | z | w |
| --- | --- | --- | --- | --- |
| 0, the fluid | velocity along x | velocity along z | density | wetness |
| 1, advected | velocity along x | velocity along z | density | |
| 2 | pressure | divergence | obstacle | height of the ground over the plane, in metres |
| 3, painted | velocity along x | velocity along z | density | mask |

Each step runs these stages of `Fluid`, in order:

1. **paint**: the brushes of the step paint layer 3, each a disc swept from where it was the step
   before, with its density and the velocity of its motion. With `obstacle_reach`, four rays
   along the plane from each cell write into layer 2 z how much of it an obstacle takes: all of
   it inside a closed mesh or next to a surface, nothing at `obstacle_reach`. With
   `ground_reach`, a ray down from that height over the cell writes into layer 2 w the height of
   the ground over the plane: the first thing it meets, terrain, foliage or a mesh. Without
   ground it is `-ground_reach`; inside a closed mesh, `ground_reach`. With `peak_height`, ground
   higher than the plane is an obstacle, a whole one at that height.
2. **composite**: the fluid takes the advected layer minus the pressure gradient, the density the
   brushes add or erase and the push of brushes and wind by density; with `downhill`, it runs down
   the slope of the ground (metres per metre) by `downhill`. It clamps the velocity, fades at the
   borders of the region and in obstacles (except what `obstacle_weaken` leaves) and leaves
   wetness, which dries.
3. **advect**: the fluid is carried back along its velocity (semi-Lagrangian), keeping what it
   keeps per step.
4. **diverge**: the divergence of the advected layer, plus what the brushes push outwards.
5. **pressure** (two iterations): a separable kernel spreads pressure and divergence along x and
   then along z and subtracts the divergence from the pressure. It is not an exact Poisson solve:
   the pressure builds up over the steps.

The region of the grid wraps in place as it follows its entity, so the fluid does not shift when
the entity moves.

The stages run on the grid of their own entity, as every first grid the stages of an unbound
program walk. Several fluids in one world, each with its own grid name, do not overlap.
`Fluid_Drift` particles and materials read one by the name of its grid, or the one the emitter
binds (`Particle_Bindings`).

## Volume

With a grid of cells along x, y and z that has a `Particle_Volume`, the last stage, **extrude**,
leaves the fluid in it as a participating medium: density becomes an elevation over the plane, a
column that rises `volume_height` metres per unit of density (`volume_below` of that under the
plane), thins upwards and opens `volume_spread` metres per metre. A noise of world cells that rises
slowly takes `volume_noise` out of it in patches of `volume_noise_size`; it glows by `volume_glow`.
The grid is the one the emitter binds to its resource `volume`, or the grid of the world with that
name (the Create card **Fluid volume** names it so); without one the stage does not run.

## Components

- `Fluid_Brush`: paints into the fluids of the world where its entity is. Each fixed tick (and
  each editor frame while not playing) `fluid_brushes` pushes a birth to the brush channel with
  its position, the velocity of its motion times `follow` plus its `push`, its `radius` and its
  `density`.
- `Fluid_Spline`: drives the fluids along a Catmull-Rom curve through its `points` (in the space
  of its entity, `count` of them). Each fixed tick `fluid_splines` pushes every span as
  `FLUID_SPLINE_STEPS` straight pieces; `paint` paints a band `width` wide around each piece,
  where the fluid runs along it at `speed` metres per second and takes `density`.
- `Fluid_Probe`: reads the fluids where its entity is, for presentation (leaves that drift, a
  sound, a wet footstep). Each fixed tick `fluid_probes` pushes its place and entity to the brush
  channel; the composite stage appends to the data channel `fluid_samples` the density, the flow
  in metres per second along the plane, the wetness and the ground height at each probe (zero
  outside the region). `fluid_samples_read` leaves in the storage `Fluid_Samples` what came back
  from the GPU in the last frame with ticks; for a probe in two fluids, the denser one.
  `fluid_sample(samples, entity)` gives the one of an entity.
- `Water_Displacer`: presses the waves of the water ([below](#water-waves)) with its submerged
  `volume` over a disc of `radius`.

## Baked states

The state of the grid of a fluid can be baked (`particle.grid.bake`) and a grid starts from it
when its `cached` names it, as every grid of the `vfx` plugin.

## Water waves

Wakes and waves of a water surface, on the same grid machinery:

- An entity with a flat two-layer `Particle_Grid` with `follow_view`, which follows what the view
  looks at, a `Particle_Emitter` whose effect runs `Water_Waves` (`shaders/water_waves.slang`)
  and a silent `Particle_Channel` named `displacers` (`CHANNEL_DISPLACERS`). Its grid is named
  `waves` (`WAVE_GRID`).
- Layer 0: height over the rest of the surface (m), its vertical speed (m/s), foam, and 1 + the
  depth of the ground under the rest (m; 0 until it was looked for). Layer 1: what materials read,
  the normal along x and z, the foam and the height. With a `vfx.Particle_World_Texture` of layer
  1 it is a world texture; shaders decode it with `fluid_waves_at` (`shaders/fluid_waves.slang`).
- The `ripple` stage (four iterations per step) carries the waves at `wave_speed` by the wave
  equation, slower than one cell in two iterations, and fades them by `damping`, more at the
  borders of the region, which absorb what reaches them.
- **Input:** each fixed tick `water_displacers` pushes the place, velocity, radius and volume of
  every `Water_Displacer` to the channel; the stage sinks the surface over the disc it sweeps
  from where it was, the volume over the area of the disc, so a moving body leaves a wake. Zero
  volume sinks nothing. With the `water` plugin, the `water_fluids` companion pushes every body
  the physics finds in the water, by what it has under the surface.
- **Foam:** where the surface rises or falls faster than `foam_speed`, where a body pushes it and,
  with `shore_depth`, where the ground is less than that depth under the surface (the shore), more
  where it touches it; it fades by `foam_fade`. A ray down from a cell finds that ground once,
  when the cell enters the region.
- The Surface program `Wave_Surface` (`shaders/wave_surface.slang`) shows the waves without the
  `water` plugin: its normals bend the surface and the foam whitens it and makes it rough.
- With `water` and the `water_fluids` companion, the surface of the water bends with the waves:
  the companion names its Surface program `Water_Fluids_Surface` (`Water_Surface` plus the slope
  of the waves, scaled by its parameter `waves`) in the setting `Water_Settings` of `water`, when
  the project leaves that setting empty. The foam is drawn over the glass of the water where the
  view meets its surface before the scene, lit by the sun and the sky.

## Particles that follow the fluid

The Vfx program `Fluid_Drift` (`shaders/fluid_drift.slang`) steers the velocity of its particles
along x and z towards that of the fluid of the grid `fluid` where they are, and density lifts them
(`rise`). Its `sim_speed` is that of the fluid.

## Outputs to materials

With a `vfx.Particle_World_Texture` of layer 0 on its grid, materials read the fluid as a world
texture. The Surface program `Fluid_Ground` (`shaders/fluid_ground.slang`) tints the ground with
`ink` by density and leaves it wet where the fluid passed: darker by `darken` and as rough as
`wet_roughness` while it dries. The grid of a fluid made in the editor is named `fluid`
(`GRID`).

## Editor

Create cards **Fluid** (grid named `fluid`, emitter and channel), **Fluid volume** (a 64×24×64
grid with `Particle_Volume`, named `volume`), **Fluid brush**, **Fluid spline** and **Fluid
probe**, each placing its recipe of `recipes/`, and the API method `fluid.samples`, the probe
samples of the shown world. A second fluid that `Fluid_Drift` or a material reads by name takes a
grid name of its own.

## Verify

In a project with the plugin, `mirai test <project>/plugins/fluids/runtime` checks that brushes push
position, motion, radius and density to the channel; a spline, its chained pieces from its first
point to its last; a displacer, its place, motion, radius and volume; a probe, its place and id,
and that what comes back through the data channel reaches `Fluid_Samples` by its entity.
`mirai test <project>/plugins/fluids/plugins/water_fluids/runtime` checks what a floating body
presses the waves with.

In the editor, with GPU validation:

- A 128×1×128 grid, an emitter with `Fluid` and its silent channel, `Fluid_Drift` particles and a
  brush that pushes: in an `editor.capture` from above, the density leaves the brush as a jet and
  opens into a plume. With a cube in the region and `obstacle_reach`, the jet does not cross it.
- A `Fluid_Spline` makes the fluid run along its curve; after baking, removing the spline and
  letting the fluid fade, naming the bake in `cached` brings the grid back to the baked state.
- A sphere with a `Water_Displacer` crossing the water leaves a V-shaped wake on `Wave_Surface`.
- A Fluid volume over the jet shows a column of smoke that follows the plume; a Fluid probe in the
  jet gives density and flow in `fluid.samples`, and zeros outside it.
- Two fluids made with the card each run on their own grid.

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
