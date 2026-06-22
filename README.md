# Scene-Dash

Scene-Dash uses an object-based ECS designed around Dart. Components are ordinary mutable objects, queries return direct references, and generated adapters handle system and bundle wiring without runtime reflection. It integrates with flutter_scene while keeping the ECS core usable on its own.

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
- [`flutter_scene` Integration](#flutter_scene-integration)
  - [Direct Node Path: Mutate Nodes Yourself](#direct-node-path-mutate-nodes-yourself)
  - [ECS-Owned Transforms](#ecs-owned-transforms)
  - [Scene Commands](#scene-commands)
- [Physics and Collisions](#physics-and-collisions)
- [How It Works](#how-it-works)
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
      ..addSystem(orbitSystem, schedule: Schedules.update);
  }
}

@System()
final class SpawnCubeSystem extends GameSystem {
  const SpawnCubeSystem();

  void run(Commands commands) {
    commands.spawn(CubeBundle());
  }
}

@System()
final class OrbitSystem extends GameSystem {
  const OrbitSystem();

  void run(
    @Query(writes: [SceneTransform, Orbit])
    Query2<SceneTransform, Orbit> movers,
    @Resource() FrameTime time,
  ) {
    movers.each((entity, transform, orbit) {
      orbit.phase += orbit.speed * time.delta;
      transform
        ..x = orbit.radius * cos(orbit.phase)
        ..z = orbit.radius * sin(orbit.phase);
    });
  }
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

Plugins insert resources:

```dart
app.insertResource<InputState>(InputState());
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

`scene_dash_flutter_scene` wraps the pure-Dart `App` in a scene-aware `Game`.
On start, it:

- exposes the real `Scene` and `SceneCommands` as resources;
- mounts entity-bound `SceneNodeRef` nodes into the scene;
- syncs optional `SceneTransform` components onto bound nodes;
- attaches one internal scene driver and exposes `game.onTick` for `SceneView`.

### Direct Node Path: Mutate Nodes Yourself

The starter example uses `SceneTransform` because it is the easiest path to
understand. When you want to avoid duplicated transform state, store a
`SceneNodeRef` and mutate the native `flutter_scene` node directly.

```dart
@ObjectComponent()
final class Orbit {
  final double radius;
  final double speed;
  double phase;

  Orbit({required this.radius, required this.speed, required this.phase});
}

@Bundle()
final class CubeBundle with _$CubeBundle {
  static final Mesh mesh =
      Mesh(CuboidGeometry(Vector3.all(0.8)), UnlitMaterial());

  final Orbit orbit;
  final SceneNodeRef node;

  CubeBundle({required double phase})
      : orbit = Orbit(radius: 3, speed: 1, phase: phase),
        node = SceneNodeRef(Node(mesh: mesh));
}

@System()
final class OrbitNodesSystem extends GameSystem {
  const OrbitNodesSystem();

  void run(
    @Query(writes: [Orbit])
    Query2<Orbit, SceneNodeRef> movers,
    @Resource() FrameTime time,
  ) {
    movers.each((entity, orbit, nodeRef) {
      orbit.phase += orbit.speed * time.delta;
      nodeRef.node.localTransform.setTranslationRaw(
        orbit.radius * cos(orbit.phase),
        0,
        orbit.radius * sin(orbit.phase),
      );
      nodeRef.node.markTransformDirty();
    });
  }
}
```

The ECS stores the node reference directly. This is less data-oriented than
Bevy, but much more natural in Flutter and Dart.

### ECS-Owned Transforms

Use `SceneTransform` when the ECS should own transform state: networking,
serialization, headless simulation, rollback, save files, or renderer
independence.

```dart
final transform = SceneTransform.zero()
  ..setTranslation(0, 1, 0)
  ..setRotationY(angle)
  ..setUniformScale(1.5);
```

`SceneTransform` is a local translation/rotation/scale component with a complete
gameplay API: translation (`setTranslation`, `translate`), scale (`setScale`,
`setUniformScale`), rotation (`setRotationX/Y/Z`, `setRotationEuler`,
`setRotationAxisAngle`, `setRotation`, and relative `rotate`/`rotateX/Y/Z`),
`lookAt`, copy/reset (`setFrom`, `setIdentity`), and a matrix escape hatch
(`setFromMatrix`, `toMatrix`). Angles are radians; forward is −Z and up is +Y.
The fields stay directly mutable, so there is no dirty tracking — helper calls
and direct field mutation are equivalent.

The integration writes it onto the bound node during `Schedules.renderSync`. Add
`PhysicsDriven` to entities whose node transform is owned by physics or another
authority, so generic sync skips them.

Games with a different transform type can use `CustomSceneSyncPlugin<T>` and
provide either a translation callback or a full matrix writer.

### Scene Commands

Use `SceneCommands` for deferred scene-graph mutations from systems.

```dart
@System()
final class AddDecorationSystem extends GameSystem {
  const AddDecorationSystem();

  void run(@Resource() SceneCommands sceneCommands) {
    sceneCommands.add(Node());
  }
}
```

## Physics and Collisions

Scene-Dash does not implement physics. Use the native `flutter_scene`
`PhysicsWorld` you want, attach it to the scene graph, then bridge that same
world into ECS with `PhysicsPlugin`.

```dart
final physics = BasicPhysicsWorld();
scene.root.addComponent(physics);

final game = Game(scene: scene)
  ..addPlugin(PhysicsPlugin(physics))
  ..addPlugin(const GameplayPlugin());
```

`BasicPhysicsWorld` is useful for picking, raycasts, overlap checks, trigger
events, and kinematic-only gameplay. It does not simulate dynamic rigid bodies.
For full rigid-body contact response, use a backend world such as a Rapier
integration; the bridge still works through the same `PhysicsWorld` interface.

Physics objects live on the `flutter_scene` node. The ECS entity usually stores
a `SceneNodeRef`, plus `PhysicsDriven` when physics owns the transform:

```dart
@Bundle()
final class PlayerBodyBundle with _$PlayerBodyBundle {
  final Player player = const Player();
  final SceneNodeRef node = SceneNodeRef(
    Node(mesh: playerMesh)
      ..addComponent(BasicKinematicBody())
      ..addComponent(
        BasicCollider(
          shape: SphereShape(radius: 0.5),
          collisionLayer: Layers.player,
          collisionMask: Layers.world | Layers.pickup,
        ),
      ),
  );

  // Skip generic SceneTransform sync; the physics body/node is authoritative.
  final PhysicsDriven physics = const PhysicsDriven();
}
```

`PhysicsPlugin` inserts the native world as `@Resource() PhysicsWorld`, so
systems can do immediate scene queries:

```dart
@System()
final class GroundProbeSystem extends GameSystem {
  const GroundProbeSystem();

  void run(
    @Query(requires: [Player]) Single<SceneNodeRef> player,
    @Resource() PhysicsWorld physics,
  ) {
    final origin = player.value.node.globalTransform.getTranslation();
    final ground = physics.raycast(
      Ray.originDirection(origin, Vector3(0, -1, 0)),
      maxDistance: 2,
      layerMask: Layers.world,
      includeTriggers: false,
    );

    if (ground == null) {
      // The player is airborne or falling.
    }
  }
}
```

For collision streams, the plugin registers `CollisionEvent` as an ECS event and
drains the native async stream at `Schedules.frameStart`.

```dart
@System()
final class ReadCollisionsSystem extends GameSystem {
  const ReadCollisionsSystem();

  void run(EventReader<CollisionEvent> collisions) {
    collisions.forEach((collision) {
      // Convert raw backend collision data into game events.
    });
  }
}
```

For larger games, treat raw collision data as a bridge boundary. Keep gameplay
semantics in your own components/resources: layers, teams, sensors, hitboxes,
damage, or entity maps. Then translate physics events or query results into
game-specific events:

```dart
final class HitEvent {
  final Entity attacker;
  final Entity target;
  final int damage;

  const HitEvent({
    required this.attacker,
    required this.target,
    required this.damage,
  });
}

@ObjectComponent()
final class CollisionMask {
  final int layer;
  final int collidesWith;

  const CollisionMask({required this.layer, required this.collidesWith});
}
```

That keeps the physics backend swappable: Scene-Dash owns scheduling, resources,
events, and queries; `flutter_scene` and the selected physics backend own
colliders, bodies, raycasts, overlap checks, and collision generation.

## How It Works

### Use Objects Instead of Fighting Dart

Trying to emulate Rust structs with generated typed-array cursors everywhere
adds complexity without a measured advantage for this use case.

The default component model remains:

```dart
@ObjectComponent()
final class Velocity {
  double x;
  double y;
  double z;

  Velocity(this.x, this.y, this.z);
}
```

Object stores are roughly:

```text
entity IDs: [4, 9, 12]
values:     [Velocity(...), Velocity(...), Velocity(...)]
```

Queries pass direct existing references to systems, and systems mutate those
objects in place.

### Code Generation Without Runtime Reflection

`source_gen` provides typed injection, generated `SystemDescriptor`s, validated
bundles, plugin metadata, access metadata, event/channel setup, and specialized
adapters while the runtime stays explicit and reflection-free.

That gives much of Bevy's authoring ergonomics without pretending Dart has
Rust's monomorphization or memory model.

System classes do not use generated mixins. The generator emits a top-level
descriptor, such as `movePlayerSystem`, and game code passes that descriptor to
`app.addSystem(...)`. Bundles still mix in their generated insert adapter, and
plugins only need a generated mixin when they declare `@GamePlugin(requires:
[...])`.

### Cache Everything Stable

Generated adapters resolve stable handles once during initialization:

- component stores;
- resources;
- event channels;
- query filters;
- iteration drivers.

A frame should not repeatedly perform service lookup, reflection, or query
construction.

### Allocate Nothing Per Matching Entity

Hot queries avoid result lists, records per entity, component copies, iterator
wrappers, temporary vectors, temporary matrices, and closures created inside the
inner loop.

The target loop is still simple:

```dart
query.each((entity, transform, velocity) {
  transform.x += velocity.x * delta;
});
```

### Drive From the Smallest Store

For a query like:

```dart
@Query(requires: [Player])
Query2<Transform, Velocity> players
```

Scene-Dash iterates whichever positive store has the fewest members, then checks
the rest through sparse arrays. This helps selective gameplay queries, even
though it is not trying to beat Bevy's table iteration for broad homogeneous
workloads.

### Avoid Duplicated Scene Data By Default

Duplicating every node transform into ECS state and syncing it every frame is
not always the best default. For visual-only state, use `SceneNodeRef` and mutate
the native node. Reach for `SceneTransform` when ECS-owned state actually buys
you serialization, rollback, networking, renderer independence, or headless
simulation.

## Packages and Examples

| Path | Purpose |
| --- | --- |
| [`packages/scene_dash`](packages/scene_dash) | Pure-Dart ECS runtime, annotations, commands, resources, events, schedules, queries. |
| [`packages/scene_dash_generator`](packages/scene_dash_generator) | `source_gen` / `build_runner` adapters for systems, bundles, and plugin metadata. |
| [`packages/scene_dash_flutter_scene`](packages/scene_dash_flutter_scene) | `Game`, `SceneNodeRef`, `SceneCommands`, `SceneTransform`, `PhysicsPlugin`, and the scene frame integration. |
| [`examples/headless_example`](examples/headless_example) | Headless generated ECS example. |
| [`examples/scene_game`](examples/scene_game) | Small `flutter_scene` app driven by Scene-Dash. |
| [`benchmarks`](benchmarks) | Pure-Dart query and structural benchmarks. |

Deep design notes live in [`docs/concept.md`](docs/concept.md), and the package
map lives in [`docs/structure.md`](docs/structure.md).

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
