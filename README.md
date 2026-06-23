# Scene-Dash

## Early prerelease

Scene-Dash is under active development. APIs may change between development releases. It is published for experimentation, examples, and design feedback.

Scene-Dash is a Bevy-inspired game framework built on top of [`flutter_scene`](https://pub.dev/packages/flutter_scene). It uses an object-based ECS designed for Dart: components are ordinary mutable objects, queries return direct references, and generated adapters handle system and bundle wiring without runtime reflection.

The ECS core can also be used independently of Flutter and `flutter_scene`.

The [`scene_game` example](https://github.com/archsolo1/scene_dash/tree/main/examples/scene_game) is the most complete reference for how Scene-Dash is intended to be used. Its [feature-oriented source structure](https://github.com/archsolo1/scene_dash/tree/main/examples/scene_game/lib) shows how gameplay is split into focused areas:

```text
lib/
├── decor/
├── fx/
├── game/
├── hud/
├── player/
├── projectiles/
├── rocks/
├── rules/
├── world/
└── main.dart
```

It demonstrates components, bundles, systems, plugins, resources, scheduling, physics integration, scene lifecycle, and Flutter UI working together in a complete example.
_________________________________________________________________________________________________________________________________________________________

```dart
final game = Game(scene: scene)
  ..addPlugin(const InputPlugin())
  ..addPlugin(const PlayerPlugin());

await game.start();

return SceneView(scene, cameraBuilder: buildCamera, onTick: game.onTick);
```

Scene-Dash **complements** `flutter_scene`; it does not replace its scene graph,
renderer, cameras, nodes, physics world, or frame loop. The integration lets ECS
systems work directly with those native objects.

## Table of Contents

- [Smallest Complete Example](#smallest-complete-example)
- [Quick Start](#quick-start)
- [Feature Tour](#feature-tour)
  - [Object Components](#object-components)
  - [Tags and Query Filters](#tags-and-query-filters)
  - [Bundles](#bundles)
  - [Commands](#commands)
  - [Resources](#resources)
  - [Events](#events)
  - [Plugins and Schedules](#plugins-and-schedules)
- [`flutter_scene` Integration](#flutter_scene-integration) — summary; full
  [integration guide](docs/integration.md)
- [Packages and Examples](#packages-and-examples)
- [Verification](#verification)

## Smallest Complete Example

Scene-Dash code is organized from the app downward:

- create a `flutter_scene` `Scene`;
- wrap it in a `Game`;
- add plugins;
- plugins register systems;
- systems query ordinary Dart objects and mutate the scene.

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash/scene_dash.dart';
import 'package:scene_dash_flutter_scene/scene_dash_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

part 'main.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Scene.initializeStaticResources();

  final scene = Scene();
  final game = Game(scene: scene)..addPlugin(const CubeOrbitPlugin());
  await game.start();

  runApp(
    MaterialApp(
      home: Scaffold(
        body: SceneView(
          scene,
          cameraBuilder: _camera,
          onTick: game.onTick,
        ),
      ),
    ),
  );
}

Camera _camera(Duration elapsed) {
  return PerspectiveCamera(
    position: Vector3(0, 3, -6),
    target: Vector3.zero(),
  );
}

@GamePlugin()
final class CubeOrbitPlugin extends Plugin {
  const CubeOrbitPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addSystem(spawnCubeSystem, schedule: Schedules.startup)
      ..addSystem(orbitCubesSystem, schedule: Schedules.update);
  }
}

@System()
void spawnCube(Commands commands) {
  commands.spawn(CubeBundle());
}

@System()
void orbitCubes(
  @Query(writes: [SceneTransform, Orbit]) Query2<SceneTransform, Orbit> movers,
  @Resource() FrameTime time,
) {
  movers.each((entity, transform, orbit) {
    orbit.phase += orbit.speed * time.delta;
    transform
      ..x = orbit.radius * cos(orbit.phase)
      ..z = orbit.radius * sin(orbit.phase);
  });
}

@ObjectComponent()
final class Orbit {
  final double radius;
  final double speed;
  double phase;

  Orbit({required this.radius, required this.speed, this.phase = 0});
}

@Bundle()
final class CubeBundle with _$CubeBundle {
  static final Mesh mesh =
      Mesh(CuboidGeometry(Vector3.all(0.8)), UnlitMaterial());

  final SceneTransform transform = SceneTransform.zero();
  final Orbit orbit = Orbit(radius: 2, speed: 1);
  final SceneNodeRef node = SceneNodeRef(Node(mesh: mesh));
}
```

Run `build_runner` to generate the system descriptors and bundle adapters:

```bash
dart run build_runner build
```

That is the whole loop: `Game` drives schedules from `SceneView`, plugins add
generated system descriptors like `spawnCubeSystem`, startup spawns an entity
with a `SceneTransform` and `SceneNodeRef`, and the integration mounts the node
and syncs the transform to `flutter_scene`.

A `@System` can be a **top-level function** (as above — the most concise form, no
class, constructor, or mixin) or a **class** that `extends GameSystem` when it
needs its own fields/state. Both generate the same kind of descriptor
(`spawnCube` → `spawnCubeSystem`), so the plugin registration is identical.

The same ECS core also works without Flutter for headless tests and simulations:

```dart
final app = App()..addPlugin(const CubeOrbitPlugin());

app.start();
app.runSchedule(Schedules.update);
```

## Quick Start

This repository is a Dart pub workspace. Because the scene integration depends on
Flutter and `flutter_scene`, resolve it from the root with Flutter:

```bash
flutter pub get
dart analyze packages/scene_dash
flutter analyze packages/scene_dash_flutter_scene
```

Generated systems, plugin dependency metadata, and bundles use `build_runner`:

```bash
cd examples/headless_example
dart run build_runner build
dart test
```

For a Flutter scene example:

```bash
cd examples/scene_game
flutter run --enable-flutter-gpu
```

## Feature Tour

The rest of the README breaks that small example apart into the features you can
combine in larger games. A typical generated file starts like this:

```dart
import 'package:scene_dash/scene_dash.dart';

part 'game.g.dart';
```

### Object Components

`@ObjectComponent()` is the normal component type. Each entity stores a
reference to an ordinary Dart object.

```dart
@ObjectComponent()
final class Velocity {
  double x;
  double y;
  double z;

  Velocity(this.x, this.y, this.z);
}
```

Systems receive the actual object and mutate it in place. There are no
snapshots, proxy objects, or component reconstruction steps.

```dart
@System()
final class AccelerateSystem extends GameSystem {
  const AccelerateSystem();

  void run(
    @Query(writes: [Velocity])
    Query1<Velocity> velocities,
  ) {
    velocities.each((entity, velocity) {
      velocity.x += 1;
    });
  }
}
```

Use object components for almost everything: health, AI state, inventories,
controllers, transforms, velocities, `flutter_scene` node references, and
game-specific state.

### Tags and Query Filters

`@Tag()` is a marker component with no per-entity object payload. Tags are useful
for filters such as player/enemy/team/state markers.

```dart
@Tag()
final class Player {
  const Player();
}

@System()
final class MovePlayersSystem extends GameSystem {
  const MovePlayersSystem();

  void run(
    @Query(writes: [Position], requires: [Player])
    Query2<Position, Velocity> players,
    @Resource() FixedTime time,
  ) {
    players.each((entity, position, velocity) {
      position
        ..x += velocity.x * time.delta
        ..y += velocity.y * time.delta;
    });
  }
}
```

Queries support positive and negative filters:

```dart
@Query(requires: [Player], excludes: [Stunned])
Query2<Position, Velocity> movers
```

For an entity that should be unique (the player, a camera rig), inject a
`Single<A>` instead of iterating — it resolves the one match and throws a clear
error on zero or many:

```dart
@System()
void readPlayer(
  @Query(requires: [Player]) Single<Position> player,
) {
  final pos = player.value; // the one Position, no loop, no null dance
}
```

`OptionalSingle<A>` allows zero matches (`.valueOrNull`) but still rejects more
than one. `Query1..4` also expose `single()`, `singleOrNull()`, and `isEmpty`.

### Bundles

`@Bundle()` is a typed spawn recipe. The generator emits the insertion code, so
one `commands.spawn(bundle)` inserts every field as a component.

```dart
@Bundle()
final class PlayerBundle with _$PlayerBundle {
  final Position position;
  final Velocity velocity;
  final Player player;
  final Health health;

  PlayerBundle({
    required this.position,
    required this.velocity,
  })  : player = const Player(),
        health = Health(100);
}

@System()
final class SpawnPlayerSystem extends GameSystem {
  const SpawnPlayerSystem();

  void run(Commands commands) {
    commands.spawn(
      PlayerBundle(
        position: Position(0, 0),
        velocity: Velocity(1, 0, 0),
      ),
    );
  }
}
```

### Commands

Structural changes are deferred until a safe schedule boundary, so sparse-set
swap removal never invalidates a running query.

```dart
void run(Commands commands) {
  final entity = commands.spawn();

  commands
      .entity(entity)
      .insert(Position(0, 0))
      .insert(Velocity(1, 0, 0));

  commands.remove<Stunned>(entity);
  commands.despawn(entity);
}
```

In debug and test builds, commands targeting stale entities trip assertions when
the command buffer is applied.

### Resources

Resources are singleton objects stored in the world. Generated systems resolve
them once during initialization and receive the same instance every run.

```dart
final class InputState {
  double horizontal = 0;
  bool jumpPressed = false;
}

@System()
final class ReadInputSystem extends GameSystem {
  const ReadInputSystem();

  void run(@Resource() InputState input) {
    if (input.jumpPressed) {
      // update gameplay state
    }
  }
}
```

Each resource is owned by one place — the plugin that uses it, or a single
insertion through the game for a dependency the Flutter widget also holds.
`insertResource` **fails loud** on a duplicate so an accidental double-registration
is caught; use `replaceResource` when swapping is intentional.

```dart
// In the owning plugin:
app.insertResource<InputState>(InputState());

// For a widget-shared instance, insert it once through the game:
final input = InputState();
final game = Game(scene: scene)
  ..addPlugin(const PlayerPlugin())
  ..insertResource<InputState>(input); // throws if PlayerPlugin already added it
```

Game code that needs direct world access can use safe helpers:

```dart
if (world.has<Health>(entity)) {
  final health = world.get<Health>(entity);
  health.value -= 10;
}

final input = world.tryResource<InputState>();
```

### Events

Events are typed channels with independent reader cursors. One system can send
an event and several systems can read it without stealing it from each other.

```dart
final class PlayerSpawned {
  final Entity entity;
  const PlayerSpawned(this.entity);
}

@System()
final class SpawnSystem extends GameSystem {
  const SpawnSystem();

  void run(Commands commands, EventWriter<PlayerSpawned> spawned) {
    final entity = commands.spawn(PlayerBundle(
      position: Position(0, 0),
      velocity: Velocity(0, 0, 0),
    ));
    spawned.send(PlayerSpawned(entity));
  }
}

@System()
final class SpawnLogSystem extends GameSystem {
  const SpawnLogSystem();

  void run(EventReader<PlayerSpawned> spawned) {
    spawned.forEach((event) {
      // handle event without allocating a result list
    });
  }
}
```

Register event ownership explicitly in a plugin:

```dart
app.addEvent<PlayerSpawned>();
```

Generated event adapters also register channels idempotently as an ergonomic
safety net.

### Plugins and Schedules

Plugins collect systems, resources, events, dependencies, and setup. They are
ordinary classes; the annotation gives the generator metadata to validate.

```dart
@GamePlugin()
final class InputPlugin extends Plugin {
  const InputPlugin();

  @override
  void build(AppBuilder app) {
    app.insertResource<InputState>(InputState());
  }
}

@GamePlugin(requires: [InputPlugin])
final class PlayerPlugin extends Plugin with _$PlayerPlugin {
  const PlayerPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addEvent<PlayerSpawned>()
      ..addSystem(spawnSystem, schedule: Schedules.startup)
      ..addSystem(movePlayersSystem, schedule: Schedules.update);
  }
}
```

Built-in schedules include frame start, fixed pre-physics, update, render sync,
startup, and shutdown. Access-conflict diagnostics can warn or error when
unordered systems both write the same component, or one writes what another
reads.

## `flutter_scene` Integration

`scene_dash_flutter_scene` wraps the pure-Dart `App` in a scene-aware `Game` that
owns the `Scene`, mounts entity-bound `SceneNodeRef` nodes before the `update`
phase (so a queried node is already in the scene), syncs `SceneTransform` onto
bound nodes, exposes a `SceneNodeIndex` (node → entity) for picking, and exposes
`game.onTick` for `SceneView`. Visual-only state can mutate native nodes directly
through `SceneNodeRef`, or the ECS can own transforms via `SceneTransform`.

Physics is not implemented by Scene-Dash: attach a native `flutter_scene`
`PhysicsWorld` and bridge it into the ECS with `PhysicsPlugin`.

See the **[integration guide](docs/integration.md)** for node mounting, transform
authority, scene commands, using `flutter_scene` features directly, and the
physics/collision bridge.

## Packages and Examples

| Path | Purpose |
| --- | --- |
| [`packages/scene_dash`](packages/scene_dash) | Pure-Dart ECS runtime, annotations, commands, resources, events, schedules, queries. |
| [`packages/scene_dash_generator`](packages/scene_dash_generator) | `source_gen` / `build_runner` adapters for systems, bundles, and plugin metadata. |
| [`packages/scene_dash_flutter_scene`](packages/scene_dash_flutter_scene) | `Game`, `SceneNodeRef`, `SceneCommands`, `SceneTransform`, `PhysicsPlugin`, and the scene frame integration. |
| [`examples/headless_example`](examples/headless_example) | Headless generated ECS example. |
| [`examples/scene_game`](examples/scene_game) | Small `flutter_scene` app driven by Scene-Dash. |
| [`benchmarks`](benchmarks) | Pure-Dart query and structural benchmarks. |

Deeper docs: the [architecture and rationale](docs/concept.md) and the
[`flutter_scene` integration guide](docs/integration.md).

## Verification

Useful checks while developing:

```bash
flutter pub get
dart analyze packages/scene_dash
flutter analyze packages/scene_dash_flutter_scene
```

Package-specific tests:

```bash
cd packages/scene_dash
dart test

cd ../scene_dash_flutter_scene
flutter test
```

The `flutter_scene` integration imports `package:flutter_scene/scene.dart` for the
0.18.x API.
