/// flutter_scene integration for scene_dash (Phase 4).
///
/// Wires the scene-agnostic core ([App]) to the `flutter_scene` lifecycle:
///
/// * [Game] — the `Game(scene:)` facade wrapping an `App`, attaching the
///   internal scene driver and exposing `onTick` for `SceneView`;
/// * [SceneTransform] / [SceneNodeRef] / [PhysicsDriven] — bind entities to
///   nodes and mark physics-owned transforms; `Game` syncs [SceneTransform]'s
///   local translation, rotation and scale and mounts bound nodes automatically
///   (use [CustomSceneSyncPlugin] only for a non-standard transform type);
/// * [SceneCommands] — deferred scene-graph mutations (also injectable into
///   systems as an `@Resource()`);
/// * [PhysicsPlugin] / [PhysicsEventBridge] — optional one-world convenience
///   for exposing a generic `PhysicsWorld` resource and buffering raw
///   `CollisionEvent`s into ECS events;
/// * [EcsFrameLoop] — the scene-free frame dispatcher (exposed for headless
///   drivers and testing).
///
/// Imports `package:flutter_scene/scene.dart` (note: the 0.18.x library is
/// `scene.dart`, not `flutter_scene.dart`).
library;

export 'src/ecs_frame_loop.dart';
export 'src/game.dart';
export 'src/physics_event_bridge.dart';
export 'src/physics_plugin.dart';
export 'src/scene_commands.dart';
export 'src/scene_mount.dart';
export 'src/scene_node_index.dart';
export 'src/scene_node_ref.dart';
export 'src/scene_sync.dart';
export 'src/scene_transform.dart';
