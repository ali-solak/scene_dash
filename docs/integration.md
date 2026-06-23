# `flutter_scene` Integration Guide

How Scene-Dash composes with `flutter_scene`: node mounting, transform authority,
scene commands, reaching native engine features, and the physics bridge. The
[README](../README.md) covers the core ECS; this is the integration detail.

## Lifecycle

`scene_dash_flutter_scene` wraps the pure-Dart `App` in a scene-aware `Game`.
On start, it:

- exposes the real `Scene` and `SceneCommands` as resources;
- mounts entity-bound `SceneNodeRef` nodes into the scene **before** the `update`
  phase (and once at startup), so a gameplay system never needs a
  `node.parent == null` guard — a queried node is already in the scene;
- syncs optional `SceneTransform` components onto bound nodes;
- exposes a `SceneNodeIndex` resource — the node → entity reverse lookup;
- attaches one internal scene driver and exposes `game.onTick` for `SceneView`.

A mounted entity also gains an integration-managed `Mounted` tag (removed on
unmount/despawn) for the rare system that wants to filter on scene-mounted
entities; bundles never author it.

## Direct node path: mutate nodes yourself

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
    // Mutating the node through SceneNodeRef counts as writing SceneNodeRef.
    @Query(writes: [Orbit, SceneNodeRef])
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

The ECS stores the node reference directly and mutates the native node, which
keeps visual-only state where `flutter_scene` already holds it.

> **Access-metadata rule:** mutating an object reached through a component (a
> `Node` or a Rapier body behind `SceneNodeRef`) counts as *writing* that
> component for scheduling diagnostics. The scheduler runs sequentially and
> cannot infer transitive mutations, so declare `writes: [SceneNodeRef]`
> whenever a system changes the referenced node or its native components.

## ECS-owned transforms

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

## Scene commands

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

## Using flutter_scene directly

Scene-Dash deliberately does **not** wrap `flutter_scene`. New engine features
become usable through two access points it already gives you, so there is no
bridge layer to keep in sync with each `flutter_scene` release:

- **Scene-wide features → `@Resource() Scene`.** A startup system mutates the
  live scene directly.
- **Per-entity features → the `Node` your `@Bundle` builds.** Add components and
  configure materials on that node like any `flutter_scene` app.

| flutter_scene feature | Reach it via |
| --- | --- |
| `antiAliasingMode` (FXAA/auto), `renderScale`, `filterQuality` | `@Resource() Scene` |
| `ambientOcclusion`, `skybox`, `skyEnvironment`, `postProcess` | `@Resource() Scene` |
| Offscreen render targets (`scene.views`, `RenderTexture`) | `@Resource() Scene` |
| `Scene.raycast` / `ScenePointer` visual picking | `@Resource() Scene` + `SceneNodeIndex` |
| `WidgetComponent` (live in-world widget) + auto input | bundle `Node` component |
| `RenderTexture` in a material slot (monitor/mirror) | bundle `Node` material |
| `InstancedMesh`, `UnlitMaterial.alphaMode`, `Node.raycastable` | bundle `Node` |
| GLB models (`Node.fromGlbAsset`, `loadScene`) | startup load → resource → bundles |

### Scene-wide settings from a startup system

```dart
@System()
void setupScene(@Resource() Scene scene) {
  scene
    ..antiAliasingMode = AntiAliasingMode.auto // MSAA where supported, else FXAA
    ..renderScale = 1.0                          // <1.0 faster, >1.0 supersamples
    ..skybox = Skybox(GradientSkySource());
  scene.ambientOcclusion
    ..enabled = true
    ..intensity = 1.1;
}
```

### Picking: `SceneNodeIndex` (node → entity)

`SceneNodeRef` is entity → node. `Scene.raycast` and `ScenePointer` return a
`Node`, so to act on the entity you hit, inject the `SceneNodeIndex` resource the
integration maintains. `entityOf` walks up ancestors, so a hit on a child mesh
still resolves to the bound entity.

```dart
@System()
void pick(
  @Resource() Scene scene,
  @Resource() SceneNodeIndex nodes,
  @Resource() PickRequest request, // your own resource holding a ray to test
) {
  final hit = scene.raycast(request.ray);
  if (hit == null) return;
  final entity = nodes.entityOf(hit.node);
  if (entity != null) {
    // act on the entity (read components, queue commands, ...)
  }
}
```

### Hardware instancing: many visuals, one draw call

For many identical visuals (foliage, debris, particles), an `InstancedMesh`
(one node, one draw call) beats one entity/node each. A startup system builds it
on the scene; an update system animates the instances **allocation-free** by
reusing a single scratch matrix (`setInstanceTransform` copies it in):

```dart
@System()
void animateMotes(@Resource() MoteField field, @Resource() FrameTime time) {
  final mesh = field.mesh;
  final scratch = field.scratch; // one Matrix4, reused every instance & frame
  for (var i = 0; i < field.count; i++) {
    scratch.setTranslationRaw(field.x[i], field.bob(i, time.delta), field.z[i]);
    mesh.setInstanceTransform(i, scratch);
  }
}
```

See [`examples/scene_game/lib/decor/decor.dart`](../examples/scene_game/lib/decor/decor.dart)
for the full feature.

## Physics and collisions

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
