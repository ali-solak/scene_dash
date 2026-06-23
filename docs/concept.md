# Scene-Dash — Concept and Architecture

Scene-Dash is an object-based ECS and plugin layer for `flutter_scene`. 


Scene-Dash is primarily an ergonomics and architecture project. It does not
assume an ECS or typed-array storage is automatically faster than straightforward
object-oriented Dart. 

## Object components

The default component model is an ordinary mutable Dart object:

```dart
@ObjectComponent()
final class Velocity {
  double x;
  double y;
  double z;

  Velocity(this.x, this.y, this.z);
}
```

Each object store is a packed sparse set:

```text
entity IDs: [4, 9, 12]
values:     [Velocity(...), Velocity(...), Velocity(...)]
```

Queries hand systems direct references to the stored objects, and systems mutate
those objects in place. There is no per-result wrapper, copy, or record.

## Code generation without runtime reflection

`source_gen` provides typed parameter injection, generated `SystemDescriptor`s,
validated bundles, plugin metadata, access metadata, and event/channel setup,
while the runtime stays explicit and reflection-free.

A `@System` is a plain class (`extends GameSystem`) or a top-level function. The
generator emits a top-level descriptor such as `movePlayerSystem` that game code
passes to `app.addSystem(...)`. Identity is `SystemRef(libraryUri, name)`, so
ordering by descriptor (`after: [readInputSystem]`) turns a rename into a compile
error rather than a silently-broken string. Bundles mix in their generated insert
adapter, and plugins need a generated mixin only when they declare
`@GamePlugin(requires: [...])`.

## Cache everything stable

Generated adapters resolve stable handles once during initialization:

- component stores;
- resources;
- event channels;
- query filters;
- iteration drivers.

A frame should not repeatedly perform service lookup, reflection, or query
construction.

## Allocate nothing per matching entity

Hot queries avoid result lists, per-entity records, component copies, iterator
wrappers, temporary vectors, temporary matrices, and closures created inside the
inner loop. The target loop stays simple:

```dart
query.each((entity, transform, velocity) {
  transform.x += velocity.x * delta;
});
```

## Drive from the smallest store

For a query like:

```dart
@Query(requires: [Player])
Query2<Transform, Velocity> players
```

Scene-Dash iterates whichever positive store has the fewest members, then checks
the rest through sparse arrays. This helps selective gameplay queries; it is not
aimed at broad homogeneous table iteration.

## Avoid duplicated scene data by default

Duplicating every node transform into ECS state and syncing it every frame is not
always the best default. For visual-only state, use `SceneNodeRef` and mutate the
native node directly. Reach for `SceneTransform` (ECS-owned transforms) when that
state actually buys serialization, rollback, networking, renderer independence,
or headless simulation.

## Access metadata is diagnostic, not enforced

`@Query(writes: [...])` declares which components a system writes; the rest of the
queried components are reads. The scheduler uses this to detect access conflicts
between unordered systems (write/write and read/write) and to validate ordering.

Dart cannot prevent mutation through an object declared read-only, and the
scheduler cannot infer transitive mutations: when a system mutates a native object
reached through a component reference (e.g. a `flutter_scene` node or a Rapier body
behind a `SceneNodeRef`), declare `writes: [SceneNodeRef]` so the metadata stays
honest. Scene-Dash runs schedules sequentially, so these declarations drive
diagnostics rather than a borrow checker.

## Optional system profiling

System execution can be measured per system and per schedule via
`AppDiagnostics(profileSystems: true)`. Profiling is off by default and adds no
per-system work when disabled. When enabled, the `SystemProfiler` resource keeps
a reusable `SystemTiming` record per (system, schedule) pair (run count,
total/latest/maximum duration, last frame) keyed by the system's stable identity
plus the schedule it ran in, and can warn when a system exceeds a configured
`slowSystemThreshold`. See the package documentation for details.
