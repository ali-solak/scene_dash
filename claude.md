# CLAUDE.md — Scene-Dash

## Project

Scene-Dash is a Bevy-inspired ECS and plugin layer for `flutter_scene`.

The objective is to provide:

- class-based plugins;
- class-based systems;
- generated system-parameter injection;
- generated bundles;
- ordinary mutable Dart objects as the default component representation;
- cached sparse-set queries;
- resources and typed events;
- safe deferred structural changes;
- direct integration with the existing `flutter_scene` lifecycle.

Scene-Dash must complement `flutter_scene`, not replace it.

Scene-Dash is primarily an ergonomics and architecture project. Do not assume that an ECS or typed-array storage is automatically faster than straightforward object-oriented Dart code.

## Read first

Before making architectural changes, read:

- `docs/concept.md` (the authoritative architecture document)
- `docs/structure.md`

Do not implement an architectural change that contradicts those documents without explaining the conflict first.

## Primary design goal

Optimize for a simple game-authoring experience:

```dart
final game = Game(scene: scene)
  ..addPlugin(InputPlugin())
  ..addPlugin(PlayerPlugin());

await game.start();

return SceneView(
  scene,
  cameraBuilder: buildCamera,
  onTick: game.onTick,
);
```

Game code should not manually manage:

- Flutter tickers;
- `CustomPainter`;
- `Canvas`;
- rendering;
- a second fixed-step accumulator;
- sparse-set indices;
- runtime reflection;
- Rapier internals.

The default game-facing API should use ordinary Dart objects and direct component references.

---

# Current public API direction

## Implemented ergonomics (current state)

These are live, tested, and exercised by the examples:

- **Systems** are `@System` classes **or** top-level `@System` functions, with
  **no `with _$…` mixin**. They are registered by a generated `SystemDescriptor`
  (`app.addSystem(movePlayerSystem, schedule: …, after: [otherSystem])`) — no
  hand-written label strings; ordering references descriptors (rename → compile
  error). Identity is `SystemRef(libraryUri, name)`.
- **`Single<A>` / `OptionalSingle<A>`** inject the one matching entity; `Query1..4`
  also have `single()` / `singleOrNull()` / `isEmpty`. Allocation note: the scan
  is allocation-free and early-exits on a second match, but `single*` returns a
  small record — for singletons/startup, not hot loops.
- **Scene mounting is automatic and ordered**: the integration runs
  commands → mount bound nodes → `update`, so gameplay never needs a
  `node.parent == null` guard. An auto-managed `Mounted` tag exists for advanced
  filtering only (never authored by bundles).
- **Resources**: `insertResource<T>` fails loud on a duplicate; `replaceResource<T>`
  swaps intentionally. Each resource is owned by one place (the plugin that uses
  it, or one insertion through the game for a widget-shared dependency).
- **Still using a generated mixin** (deliberately, for now): `@Bundle` classes
  (`with _$YourBundle`) and `@GamePlugin(requires: …)` (`with _$YourPlugin`).
  Removing these cleanly would need a runtime registry, which was evaluated and
  rejected (import-side-effect risk); the one-line mixin is the lesser cost.
- **No global registry**: descriptors made registration concise without one.

## Plugin

Plugins are explicit classes:

Systems are registered by their **generated descriptor** (a top-level value the
generator emits next to each `@System`), not by a hand-written label string.
Ordering references other descriptors, so a rename is a compile error:

```dart
@GamePlugin()
final class PlayerPlugin extends Plugin {
  const PlayerPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addEvent<PlayerSpawned>()
      ..addSystem(spawnPlayerSystem, schedule: Schedules.startup)
      ..addSystem(readPlayerInputSystem, schedule: Schedules.fixedPrePhysics)
      ..addSystem(
        movePlayerSystem,
        schedule: Schedules.fixedPrePhysics,
        after: [readPlayerInputSystem],
      );
  }
}
```

`spawnPlayerSystem` etc. are generated `SystemDescriptor`s (identity =
library URI + declared name). There is no `label:` and no `with _$…` mixin on the
system class. Do not replace plugins themselves with function plugins unless
explicitly requested.

## System

A `@System` is a class with a synchronous `run(...)` (no `with _$…` mixin), or a
top-level `@System` function — the function form is the most concise and is
preferred for stateless systems. Parameters are injected by the generated adapter:

```dart
@System()
final class MovePlayerSystem extends GameSystem {
  const MovePlayerSystem();

  void run(
    @Query(writes: [Transform], requires: [Player], excludes: [Disabled])
    Query2<Transform, Velocity> players,
    @Resource() FixedTime time,
  ) {
    players.each((entity, transform, velocity) {
      transform
        ..x += velocity.x * time.delta
        ..y += velocity.y * time.delta;
    });
  }
}

// Equivalent top-level function system (no class/constructor ceremony):
@System()
void movePlayer(
  @Query(writes: [Transform], requires: [Player]) Query2<Transform, Velocity> players,
  @Resource() FixedTime time,
) { /* ... */ }
```

Injectable parameter types: `Query1..Query4`, `Single<A>` / `OptionalSingle<A>`
(resolve the one matching entity — see below), `@Resource() T`, `Commands`,
`EventReader<T>`, `EventWriter<T>`. The `run`/function must remain synchronous.

### Singleton access: `Single<A>` / `OptionalSingle<A>`

For an entity known to be unique (the player, a camera rig), inject a `Single`
instead of iterating a query:

```dart
@System()
void evaluateRules(
  @Query(requires: [Player]) Single<SceneNodeRef> player,
  @Resource() GameState game,
) {
  final node = player.value.node; // throws if not exactly one match
}
```

`OptionalSingle<A>` tolerates zero matches (`.valueOrNull`) but still throws on
more than one. `Query1..4` also expose `single()` / `singleOrNull()` / `isEmpty`.
Do not require systems to retrieve queries or resources from a context or locator.

## Component

Components are ordinary mutable Dart objects:

```dart
@Component()
final class Transform {
  double x;
  double y;
  double z;

  Transform(this.x, this.y, this.z);
}
```

The component object is authoritative runtime state.

Queries return direct references to stored objects. Do not reconstruct components or wrap every result in a generated cursor object.

Because `flutter_scene` also defines a `Component` class, use import prefixes or selective imports when needed:

```dart
import 'package:scene_dash/scene_dash.dart' as ecs;
import 'package:flutter_scene/flutter_scene.dart' as scene;
```

```dart
@ecs.Component()
final class SceneNodeRef {
  final scene.Node node;

  const SceneNodeRef(this.node);
}
```

Do not add separate `@ObjectComponent()` and `@PackedComponent()` annotations to the initial API.

## Tag

```dart
@Tag()
final class Player {
  const Player();
}
```

Tags store entity membership without a payload.

## Bundle

```dart
@Bundle()
final class PlayerBundle {
  final Transform transform;
  final Velocity velocity;
  final Player player;

  PlayerBundle()
      : transform = Transform(0, 2, 0),
        velocity = Velocity(0, 0, 0),
        player = const Player();
}
```

Bundle insertion code is generated.

---

# Storage model

## Entity registry

Use:

```text
Uint32List generations
Uint8List alive
Uint32List freeIndices
```

Entities must use generational handles so stale entity references cannot address reused indices.

## Object component store

Use:

```text
Uint32List denseEntities
Uint32List sparse
List<T> values
```

The object in `values` is the authoritative component value.

## Tag store

Use:

```text
Uint32List denseEntities
Uint32List sparse
```

All stores use:

- geometric capacity growth;
- packed dense rows;
- swap removal;
- zero as the missing sparse sentinel;
- `denseIndex + 1` in sparse arrays.

Do not introduce per-entity component maps in hot paths.

## Optional future packed storage

Packed typed-array storage is not part of the initial implementation.

A future specialized store may use:

```text
Uint32List denseEntities
Uint32List sparse
Float64List / Float32List / Int32List fields
```

Only add packed storage when:

1. a representative benchmark shows a meaningful advantage;
2. object sparse queries are already correct;
3. mobile release-mode results support the change;
4. the packed implementation does not complicate the normal object-component API.

Do not create packed-store runtime files or generator files during the initial implementation.

---

# Query implementation

A query must cache:

- direct component-store references;
- tag and filter-store references;
- read/write metadata;
- its iteration plan.

A cached query must not permanently cache matching entity IDs.

On every execution:

1. Choose the smallest positive component or tag store as the driver.
2. Iterate its dense entity array.
3. Use sparse arrays to check other required components.
4. Check `with` and `without` filters.
5. Read matching component objects directly from store `values`.
6. Invoke the query callback.

Conceptually:

```dart
for (var i = 0; i < driver.length; i++) {
  final entityIndex = driver.denseEntities[i];

  final transformIndex =
      transforms.denseIndexOf(entityIndex);

  if (transformIndex < 0) {
    continue;
  }

  final velocityIndex =
      velocities.denseIndexOf(entityIndex);

  if (velocityIndex < 0) {
    continue;
  }

  if (!players.contains(entityIndex)) {
    continue;
  }

  if (disabled.contains(entityIndex)) {
    continue;
  }

  callback(
    entities.resolve(entityIndex),
    transforms.values[transformIndex],
    velocities.values[velocityIndex],
  );
}
```

Do not:

- build result lists;
- copy components per result;
- allocate a record for every result;
- allocate a wrapper object per result;
- perform per-entity map lookups;
- expose sparse-set indices to game code.

The normal API is:

```dart
query.each((entity, componentA, componentB) {
  // ...
});
```

Initial query types:

```text
Query1<A>
Query2<A, B>
Query3<A, B, C>
Query4<A, B, C, D>
```

Do not add higher arities until real use cases justify them.

## Query access metadata

The `writes` declaration provides scheduling metadata:

```dart
@Query(
  writes: [Transform],
)
Query2<Transform, Velocity> entities
```

This declares that the system writes `Transform` and reads `Velocity`.

Use this metadata for:

- conflict diagnostics;
- schedule validation;
- documentation;
- possible future optimization.

Dart cannot fully prevent mutation through an object declared read-only. Do not attempt to build Rust-style borrow checking around mutable Dart objects.

---

# Generated code

The generator may produce:

- component descriptors;
- tag descriptors;
- bundle adapters;
- system adapters;
- plugin descriptors;
- parameter wiring;
- validation diagnostics.

For each `@System` the generator emits a **public** adapter class and a top-level
`SystemDescriptor` (no `with _$…` mixin). The adapter resolves queries and
resources during `initialize`; the descriptor pairs the system's stable
`SystemRef` identity with an adapter factory:

```dart
class $MovePlayerSystemAdapter
    implements SystemAdapter, SystemAccessProvider {
  $MovePlayerSystemAdapter(this._system);
  final MovePlayerSystem _system;

  late final Query2<Transform, Velocity> _p0;
  late final FixedTime _p1;

  @override
  void initialize(World world) {
    world.ensureObjectStore<Transform>();
    world.ensureObjectStore<Velocity>();
    world.ensureTagStore<Player>();
    _p0 = world.query2<Transform, Velocity>(
      withTypes: const [Player],
      withoutTypes: const [Disabled],
    );
    _p1 = world.resources.get<FixedTime>();
  }

  @override
  SystemAccess get access => const SystemAccess(
        reads: <Type>{Velocity},
        writes: <Type>{Transform},
      );

  @override
  void run() => _system.run(_p0, _p1);
}

// Game code registers the system by passing this descriptor to `addSystem`.
final movePlayerSystem = SystemDescriptor(
  const SystemRef('package:my_game/player.dart', 'MovePlayerSystem'),
  () => $MovePlayerSystemAdapter(const MovePlayerSystem()),
);
```

A top-level `@System` function generates the same adapter, but `run()` calls the
function directly (no `_system` field). All stores, queries, resources, and event
handles must be resolved before frame execution begins.

The initial generator must not generate:

- packed typed-array fields;
- packed component cursor references;
- snapshot APIs;
- reference-lifetime guards;
- precision metadata;
- packed-store growth logic.

---

# Scheduling

Initial schedules:

```text
startup
frameStart
fixedPrePhysics
update
renderSync
shutdown
```

Do not add `fixedPostPhysics` until `flutter_scene` provides a stable public post-step hook.

Schedules are compiled once at startup.

System ordering references other systems by their generated descriptors (a
rename becomes a compile error). Internally each descriptor's `SystemRef`
produces a stable `SystemLabel` (`library#name`) that the schedule graph keys on:

```dart
app.addSystem(
  movePlayerSystem,
  schedule: Schedules.fixedPrePhysics,
  after: [readPlayerInputSystem],
);
```

Hand-written `addSystemAdapter(adapter, schedule:, label:)` with an explicit
`SystemLabel` remains for integration/test adapters that have no generated
descriptor.

Reject:

- duplicate labels;
- missing dependencies;
- dependency cycles;
- system registration after schedules are frozen.

Warn or fail in debug mode when unordered systems have conflicting access metadata.

Access metadata is diagnostic in the object-based architecture. It is not enforced through a borrow checker.

---

# Structural changes

Component field changes are immediate:

```dart
transform.x += 1;
health.current -= 10;
```

Structural changes are deferred:

```dart
commands.spawn(bundle);
commands.insert(entity, component);
commands.remove<Component>(entity);
commands.despawn(entity);
```

Apply commands once after the current schedule.

Never perform sparse-set insertion, removal, or despawning while a query is active.

Scene graph mutations use a separate `SceneCommands` buffer.

---

# `flutter_scene` integration

`SceneView` is the only Flutter frame host:

```dart
SceneView(
  scene,
  cameraBuilder: buildCamera,
  onTick: game.onTick,
)
```

Do not create:

- another ticker;
- another painter;
- another render loop;
- a required camera node;
- a required `CameraComponent`;
- a custom camera abstraction.

`cameraBuilder` or `viewsBuilder` remain normal `flutter_scene` APIs.

`Game.start()` attaches one internal component to the scene root.

Conceptual lifecycle:

```text
SceneView.onTick
    frameStart schedule

flutter_scene fixed step
    internal ECS driver fixedUpdate
    fixedPrePhysics schedule
    PhysicsWorld.step

flutter_scene interpolation

flutter_scene component update
    ECS update schedule
    ECS renderSync schedule

SceneView render
```

The ECS must not own another fixed-step accumulator.

## Scene synchronization

`SceneNodeRef` is an object component:

```dart
@Component()
final class SceneNodeRef {
  final Node node;

  const SceneNodeRef(this.node);
}
```

Transform synchronization should mutate the existing matrix and mark it dirty:

```dart
binding.node.localTransform.setTranslationRaw(
  transform.x,
  transform.y,
  transform.z,
);

binding.node.markTransformDirty();
```

Do not allocate a new `Matrix4` or temporary vector per entity during synchronization.

Changed-only synchronization is a valid optimization independent of component storage. Add it after the basic synchronization path is correct and measured.

---

# Physics boundary

The ECS core must not import `flutter_scene_rapier`.

Generic integration targets public `flutter_scene` physics abstractions.

Rapier-specific behavior belongs in an optional package.

Do not:

- subclass `RapierWorld`;
- override Rapier internals;
- depend on undocumented collision-drain order;
- promise same-substep collision delivery without a stable public hook.

---

# Package structure

```text
packages/
  scene_dash/
    Pure Dart ECS runtime and public annotations

  scene_dash_generator/
    source_gen/build_runner generator

  scene_dash_flutter_scene/
    flutter_scene lifecycle and scene bridge

  scene_dash_rapier/
    Optional future Rapier-specific extensions
```

## `scene_dash`

Owns:

- entities;
- object component stores;
- tag stores;
- sparse-set queries;
- resources;
- events;
- commands;
- systems;
- schedules;
- plugins;
- annotations;
- generated-code interfaces.

Must not depend on Flutter, `flutter_scene`, Rapier, analyzer, or `source_gen`.

## `scene_dash_generator`

Owns generation for:

- component descriptors;
- tag descriptors;
- bundles;
- system adapters;
- plugin metadata;
- compile-time validation.

Depends on:

- `scene_dash`;
- `analyzer`;
- `build`;
- `source_gen`.

Do not add packed-store generation during the initial implementation.

## `scene_dash_flutter_scene`

Owns:

- internal scene driver;
- `SceneCommands`;
- `SceneNodeRef`;
- transform synchronization;
- transform authority rules;
- generic physics-world integration;
- physics-event buffering.

It does not own Flutter HUDs, overlays, navigation, or application state.

## `scene_dash_rapier`

Do not create until a demonstrated requirement cannot be handled through generic `flutter_scene` physics APIs.

---

# Implementation order

Follow this order unless a task explicitly requires otherwise.

## Phase 1: Runtime correctness

1. `Entity` and generational registry.
2. `ObjectComponentStore<T>`.
3. `TagStore`.
4. Store registry.
5. `World`.
6. Resources.
7. Deferred commands.
8. `Query1`.
9. `Query2`.
10. Basic schedules.
11. `Game`.
12. Manual system adapters for tests.
13. Events.

At the end of this phase, the ECS must work without code generation.

## Phase 2: Generator foundation

1. Annotation readers.
2. Component validation.
3. Component descriptor generation.
4. Tag descriptor generation.
5. Bundle generation.
6. System adapter generation.
7. Resource and event parameter wiring.
8. Plugin metadata generation.
9. Golden tests.

At this point, object components and generated systems should work end to end.

## Phase 3: Query and scheduling behavior

1. Query filters.
2. Smallest-store driver selection.
3. Query-plan caching.
4. `Query3`.
5. `Query4`.
6. System labels.
7. Dependency graph.
8. Topological sorting.
9. Cycle detection.
10. Access-conflict diagnostics.
11. Schedule freezing.

## Phase 4: `flutter_scene`

1. Internal scene driver.
2. Frame-start integration.
3. `SceneNodeRef`.
4. Generic transform synchronization.
5. Transform authority rules.
6. Scene command queue.
7. Generic physics bridge.
8. Physics-event buffering where supported.

## Phase 5: Change tracking and measured optimization

Only optimize after benchmarks identify a bottleneck.

Possible work:

1. Component change versions.
2. Changed-only scene synchronization.
3. Command-buffer reuse.
4. Event-buffer reuse.
5. Store growth tuning.
6. Generated specialized query loops.

## Phase 6: Optional packed storage

Only begin this phase when a representative workload demonstrates a meaningful advantage.

Possible work:

1. Packed-component annotation design.
2. Typed-array field mapping.
3. Generated packed stores.
4. Packed query access.
5. Object sparse query versus typed sparse query benchmarks.
6. Mobile release-mode validation.

Packed storage is not required for the initial release.

---

# Testing requirements

Every change must include appropriate tests.

## Required runtime tests

- generational entity reuse;
- stale entity rejection;
- object-store insertion;
- object-store replacement;
- object-store removal;
- swap removal;
- object-store capacity growth;
- tag filtering;
- `with` and `without` query filtering;
- `Query1` behavior;
- `Query2` behavior;
- deferred structural changes;
- resources;
- independent event readers;
- dependency sorting;
- cycle detection;
- access-conflict diagnostics;
- schedule freezing.

## Required generator tests

- valid object component;
- tag;
- bundle;
- query parameter generation;
- resource injection;
- event reader injection;
- event writer injection;
- invalid async system;
- invalid `writes` entry;
- plugin metadata.

Prefer golden tests for generated code.

Do not add initial tests for:

- packed component generation;
- typed-array field mapping;
- component cursor references;
- snapshot generation;
- reference-lifetime guards.

## Integration tests

- game starts and attaches the scene driver;
- fixed systems run at the expected lifecycle point;
- update systems run in the expected order;
- render sync updates scene nodes;
- node matrices are mutated without per-entity allocation;
- scene commands flush safely;
- plugin dependencies are validated;
- Flutter HUD remains external to Scene-Dash.

---

# Performance requirements

Benchmark before making performance claims.

At minimum benchmark:

- flat `List<Actor>` iteration;
- object sparse `Query1`;
- object sparse `Query2`;
- filtered object query;
- tag filtering;
- component insertion;
- component removal;
- spawning;
- despawning;
- command application;
- changed-only scene synchronization.

Keep the existing typed-array benchmark as a comparison and regression tool.

Compare:

```text
Flat object loop
Object sparse query
Float64List loop
Typed sparse query
```

This isolates the architectural cost of sparse queries from the component representation.

Do not claim that sparse-set queries are faster than direct object loops unless measurements support the claim.

Do not rely only on microbenchmarks. Include at least one representative scene workload with:

```text
10,000 gameplay entities
1,000 visible scene nodes
multiple component filters
regular spawning and despawning
changed-only node synchronization
```

Where possible, capture rendered Flutter frame and raster timings on a release-mode mobile target.

Hot query loops must not allocate:

- component copies;
- result lists;
- per-result records;
- per-entity wrapper objects.

Do not claim deterministic simulation merely because a fixed timestep is used.

---

# Coding conventions

- Use `final class`, `base class`, `sealed class`, and extension types where they improve API guarantees.
- Prefer explicit APIs over dynamic dispatch in hot paths.
- Avoid `dynamic` in runtime ECS code.
- Avoid runtime reflection.
- Avoid global mutable registries.
- Keep public classes documented.
- Keep generated implementation types private when possible.
- Use `dart format`.
- Run `dart analyze`.
- Do not suppress analyzer errors without explaining why.
- Keep runtime packages null-safe.
- Do not expose sparse-set indices as the normal game API.
- Do not introduce packed-storage complexity without benchmark evidence.

---

# Commands

Run formatting:

```bash
dart format .
```

Run analysis:

```bash
dart analyze
```

Run tests:

```bash
dart test
```

Generate code once:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Watch generated code:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Run benchmarks:

```bash
dart run benchmarks/object_query_benchmark.dart
```

---

# Working rules for Claude

Before implementing a task:

1. Read the relevant architecture and structure documents.
2. Inspect the relevant public API and tests.
3. State which package owns the change.
4. Preserve the dependency boundaries in this file.
5. Implement the smallest complete vertical slice.
6. Add or update tests.
7. Run formatting, analysis, and relevant tests.
8. Report architectural assumptions that could not be verified.

When implementation details are unclear:

- choose correctness over speculative optimization;
- preserve the game-facing API;
- use ordinary object components by default;
- add a focused proof of concept before building a large generator;
- benchmark object sparse queries before optimizing query internals;
- do not invent `flutter_scene` APIs;
- verify current APIs from the installed dependency or official source.

Do not silently redesign the public API.

Do not add packed typed-array storage, cursor references, or snapshot machinery unless the task explicitly targets the optional packed-storage phase and includes benchmark justification.

Scene-Dash is a focused gameplay-data and systems layer, not a replacement for Flutter application architecture or state management. HUDs, menus, and other UI should continue to use normal Flutter widgets, composition, and whichever state-management approach the application chooses.
