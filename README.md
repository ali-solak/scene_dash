# Scene-Dash

Scene-Dash is a Bevy-inspired game framework built on top of
[`flutter_scene`](https://pub.dev/packages/flutter_scene). It gives your game
logic a structure that scales: components are plain Dart objects, systems are
plain functions, and `build_runner` generates the wiring.

It does not replace `flutter_scene` — the scene graph, renderer, cameras and
physics stay native. Scene-Dash adds the game structure around them. The core
also runs without Flutter, so game logic is easy to test headless.

## A complete game in one file

One orbiting cube:

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
        body: SceneView(scene, cameraBuilder: _camera, onTick: game.onTick),
      ),
    ),
  );
}

Camera _camera(Duration elapsed) =>
    PerspectiveCamera(position: Vector3(0, 3, -6), target: Vector3.zero());

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
void spawnCube(Commands commands) => commands.spawn(CubeBundle());

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
  static final Mesh mesh = Mesh(CuboidGeometry(Vector3.all(0.8)), UnlitMaterial());

  final SceneTransform transform = SceneTransform.zero();
  final Orbit orbit = Orbit(radius: 2, speed: 1);
  final SceneNodeRef node = SceneNodeRef(Node(mesh: mesh));
}
```

Generate the wiring for the annotations:

```bash
dart run build_runner build
```

The generator turns each `@System` function into a registrable descriptor named
after it (`spawnCube` → `spawnCubeSystem`) and creates the `_$CubeBundle` mixin
— all in `main.g.dart`. So those names don't exist until the first build; use
`dart run build_runner watch` while developing. Rule of thumb: a `@Bundle`
always needs its `with _$Name` mixin; a `@GamePlugin` only needs one when it
declares `requires:`.

## Quick start

The repository is a pub workspace; resolve it from the root:

```bash
flutter pub get
```

Run the example game (`flutter_scene` needs Flutter GPU, which is only on the
**master** channel: `flutter channel master`):

```bash
cd examples/scene_game
dart run build_runner build
flutter run --enable-flutter-gpu
```

## The building blocks

A game is a set of features. Each feature is a **plugin** that registers
**systems**; systems query **components** and talk to each other through
**events** and **resources**.

### Plugins

A plugin registers a feature's systems and picks their schedules. Schedules run
in frame order: `frameStart`, `fixedPrePhysics`, `update`, `renderSync`, plus
once-only `startup` and `shutdown`.

```dart
@GamePlugin(requires: [InputPlugin])
final class PlayerPlugin extends Plugin with _$PlayerPlugin {
  const PlayerPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addSystem(spawnPlayerSystem, schedule: Schedules.startup)
      ..addSystem(movePlayerSystem, schedule: Schedules.fixedPrePhysics);
  }
}
```

`main` wires the scene, game and plugins, then hands the scene to `SceneView`:

```dart
final scene = Scene();
final game = Game(scene: scene)
  ..addPlugin(const InputPlugin())
  ..addPlugin(const PlayerPlugin());
await game.start();

runApp(MyGameApp(scene: scene, game: game));
```

### Systems

A system is a function (or a class, if it needs state) whose parameters declare
what it uses. `@Query` hands you matching components directly; `@Resource`
injects shared state.

```dart
@System()
void applyVelocity(
  @Query(writes: [SceneTransform], excludes: [Stunned])
  Query2<SceneTransform, Velocity> movers,
  @Resource() FixedTime time,
) {
  movers.each((entity, transform, velocity) {
    transform
      ..x += velocity.x * time.delta
      ..z += velocity.z * time.delta;
  });
}
```

The `writes:` list declares which components the system mutates. It changes
nothing at runtime — the scheduler uses it to warn when two unordered systems
touch the same data.

`Single<A>` resolves a unique entity like the player; `OptionalSingle<A>`
allows zero. Resolving re-runs the query, so grab `.value` once per system,
not inside a loop. Spawning and despawning go through `Commands`, which defers
the change to a safe point so it never breaks a running query:

```dart
@System()
void spawnEnemy(Commands commands) {
  final enemy = commands.spawn();
  commands
      .entity(enemy)
      .insert(const Enemy())
      .insert(Health(30))
      .insert(Velocity(0, -2));
}
```

### Run conditions

Instead of starting every system with `if (game.status != playing) return;`,
declare when it runs. The condition is checked every pass, and the system is
skipped while it returns false:

```dart
bool playing(World world) =>
    world.resource<GameState>().status == GameStatus.playing;

app.addSystem(movePlayerSystem, schedule: Schedules.fixedPrePhysics, runIf: playing);
```

### Components and tags

Components hold data and are mutated in place. Tags are empty markers used to
filter queries.

```dart
@ObjectComponent()
final class Health {
  double current;
  final double max;
  Health(this.max) : current = max;
}

@Tag()
final class Enemy {
  const Enemy();
}
```

### Bundles

A bundle is a spawn recipe: `commands.spawn(bundle)` inserts every field as a
component.

```dart
@Bundle()
final class PlayerBundle with _$PlayerBundle {
  final Player player = const Player();
  final Health health = Health(100);
  final Velocity velocity = Velocity(0, 0);
  final SceneNodeRef node = SceneNodeRef(Node(mesh: _mesh));

  static final Mesh _mesh = Mesh(SphereGeometry(radius: 0.5), UnlitMaterial());
}
```

### Events

Events let one feature announce something and others react without knowing
each other. Register the channel in the owning plugin with
`app.addEvent<EnemyKilled>()`.

```dart
@System()
void resolveEnemyDeaths(
  @Query(requires: [Enemy]) Query2<Health, SceneTransform> enemies,
  Commands commands,
  EventWriter<EnemyKilled> killed,
) {
  enemies.each((entity, health, transform) {
    if (health.current > 0) return;
    killed.send(EnemyKilled(transform.translation.clone(), 10));
    commands.despawn(entity);
  });
}

@System()
void awardBounty(EventReader<EnemyKilled> killed, @Resource() Score score) {
  killed.forEach((event) => score.value += event.bounty);
}
```

An event stays readable for the frame it was sent plus the next one, so a
system that reads every frame never misses anything. A reader that skips
frames (paused, or gated by `runIf`) misses the older events instead of piling
them up — a diagnostic reports it once if that happens. Pass
`retainedUpdates: null` to `addEvent` to keep events until every reader has
consumed them.

### Resources

Resources are world singletons: input, score, config, a database handle.

```dart
final class Score {
  int value = 0;
}

@System()
void showScore(@Resource() Score score) {
  // ...
}
```

A plugin owns its resources (`app.insertResource`). Something built in `main`,
like a database, is inserted through the game instead:

```dart
final game = Game(scene: scene)
  ..insertResource<SaveRepo>(SaveRepo(db))
  ..addPlugin(const SavePlugin());
```

## Rendering

Your game data lives in the world as plain objects in flat arrays; everything
you see is a real, unwrapped `flutter_scene` `Node`. A `SceneNodeRef`
component is the only bridge between the two — so any native feature is one
`node.addComponent(...)` away. The full reasoning is in
[architecture and rationale](docs/concept.md).

`Game` wraps the pure-Dart `App` and connects it to `flutter_scene`:

- the live `Scene` and `SceneCommands` are available as resources;
- entity-bound `SceneNodeRef` nodes are mounted into the scene automatically;
- a `SceneTransform` component is synced onto the bound node every frame;
- `SceneNodeIndex` maps a hit node back to its entity for picking.

An entity's transform can live in the ECS (add a `SceneTransform`) or on the
node itself (store only a `SceneNodeRef` and mutate the node). Add the
`PhysicsDriven` tag when a physics body owns the transform.

Details, including scene commands and picking, are in the
[integration guide](docs/integration.md).

## Physics

Scene-Dash has no physics of its own. Attach a native `flutter_scene` physics
world (for example `flutter_scene_rapier`) to the scene, then bridge it into
the ECS with `PhysicsPlugin`:

```dart
final physics = RapierWorld(gravity: Vector3(0, -9.81, 0));
final scene = Scene()..root.addComponent(physics);

final game = Game(scene: scene)
  ..addPlugin(PhysicsPlugin(physics))
  ..addPlugin(const PlayerPlugin());
```

Systems query the world directly as a resource:

```dart
@System()
void probeGround(@Resource() PhysicsWorld physics) {
  final hit = physics.raycast(ray, maxDistance: 1.1);
  // ...
}
```

Collisions arrive as a regular ECS event:

```dart
@System()
void readCollisions(EventReader<CollisionEvent> collisions) {
  collisions.forEach((collision) {
    // ...
  });
}
```

The full walkthrough — bodies, colliders, layers, triggers, character
controllers — is in the
[integration guide](docs/integration.md#physics-and-collisions).

## Packages and examples

| Path | Purpose |
| --- | --- |
| [`packages/scene_dash`](packages/scene_dash) | Pure-Dart ECS runtime. |
| [`packages/scene_dash_generator`](packages/scene_dash_generator) | Code generation for the annotations. |
| [`packages/scene_dash_flutter_scene`](packages/scene_dash_flutter_scene) | The `flutter_scene` integration: `Game`, node mounting, transform sync, physics bridge. |
| [`examples/scene_game`](examples/scene_game) | Complete game: `flutter_scene` + Rapier, one plugin per feature. |
| [`examples/headless_example`](examples/headless_example) | The ECS core running without Flutter. |
| [`benchmarks`](benchmarks) | Query and structural benchmarks. |

The [`scene_game` example](examples/scene_game) is the best reference. Each
folder is one feature with its own components, bundles, systems and resources:

```text
lib/
├── player/
├── projectiles/
├── rocks/
├── collectables/
├── world/
├── hud/
└── main.dart
```

Deeper docs: [architecture and rationale](docs/concept.md) and the
[integration guide](docs/integration.md).

## Development

```bash
flutter pub get

cd packages/scene_dash && dart test
cd packages/scene_dash_flutter_scene && flutter test
```
