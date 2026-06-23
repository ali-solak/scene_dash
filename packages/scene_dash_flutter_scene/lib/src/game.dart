import 'package:flutter_scene/scene.dart' show Node, Scene;
import 'package:scene_dash/scene_dash.dart';

import 'ecs_frame_loop.dart';
import 'scene_commands.dart';
import 'scene_driver.dart';
import 'scene_mount.dart';
import 'scene_node_index.dart';
import 'scene_sync.dart';
import 'scene_transform.dart';

/// The scene-aware facade over the core [App].
///
/// `Game` composes an [App] with a `flutter_scene` [Scene] and installs the
/// standard scene integration automatically, so feature plugins register only
/// their own systems. On [start] it:
///
/// * exposes the real [Scene] and [SceneCommands] as `@Resource()`s;
/// * auto-mounts entity-bound nodes ([SceneNodeRef]) into the scene;
/// * synchronizes the standard [SceneTransform] onto bound nodes each frame;
/// * attaches the internal [EcsSceneDriver] and exposes [onTick] for `SceneView`.
///
/// (Use `CustomSceneSyncPlugin<T>` only for a non-standard transform type.)
///
/// ```dart
/// await Scene.initializeStaticResources();
/// final scene = Scene();
/// final game = Game(scene: scene)
///   ..addPlugin(const InputPlugin())
///   ..addPlugin(const PlayerPlugin());
/// await game.start();
///
/// return SceneView(scene, cameraBuilder: buildCamera, onTick: game.onTick);
/// ```
final class Game {
  /// The app-owned scene this game renders into.
  final Scene scene;

  /// The underlying scene-agnostic engine.
  final App app;

  /// Deferred scene-graph mutations, flushed once per frame (and after
  /// startup). Also injectable into systems as an `@Resource()`.
  late final SceneCommands sceneCommands = SceneCommands(scene.root);

  /// Live node → entity index, exposed to systems as a [SceneNodeIndex] resource
  /// and maintained by the mount adapter.
  final Map<Node, Entity> _nodeIndex = <Node, Entity>{};

  /// Mounts entity-bound nodes into the scene. Owned by `Game` (not registered
  /// in a schedule) so it can run *before* the `update` phase — see [_mountStep].
  late final SceneNodeMountAdapter _mountAdapter =
      SceneNodeMountAdapter(sceneCommands, _nodeIndex);

  late final EcsFrameLoop _loop = EcsFrameLoop(
    app,
    onBeforeUpdate: _mountStep,
    onFrameEnd: sceneCommands.flush,
  );

  /// Mounts newly bound nodes and flushes them, so a gameplay `update` system
  /// sees already-parented (and `Mounted`-tagged) nodes. Runs before the
  /// `update` schedule each frame, and once at startup.
  void _mountStep() {
    _mountAdapter.run();
    sceneCommands.flush();
  }

  bool _started = false;
  bool _shutdown = false;
  EcsSceneDriver? _driver;

  Game({
    required this.scene,
    AccessConflictPolicy accessConflictPolicy = AccessConflictPolicy.warn,
    void Function(String message)? onDiagnostic,
  }) : app = App(
          accessConflictPolicy: accessConflictPolicy,
          onDiagnostic: onDiagnostic,
        );

  /// The ECS world.
  World get world => app.world;

  /// Registers [plugin]. Mirrors [App.addPlugin] for fluent setup.
  Game addPlugin(Plugin plugin) {
    app.addPlugin(plugin);
    return this;
  }

  /// Inserts an externally-constructed resource (e.g. one the Flutter widget
  /// also holds) before [start]. The single authoring path for resources —
  /// fails loud on a duplicate; use [replaceResource] to swap intentionally.
  Game insertResource<T extends Object>(T resource) {
    app.insertResource<T>(resource);
    return this;
  }

  /// Replaces (or inserts) a resource before [start]. Use when swapping is
  /// intentional.
  Game replaceResource<T extends Object>(T resource) {
    app.replaceResource<T>(resource);
    return this;
  }

  /// Finalizes the app and attaches the scene driver to the scene root.
  ///
  /// Call `await Scene.initializeStaticResources()` before rendering (as the
  /// `flutter_scene` examples do); it is not this method's responsibility.
  Future<void> start() async {
    if (_started) {
      throw StateError('Game has already been started.');
    }
    _loop.ensureTimeResources();
    // Expose the real flutter_scene Scene and the deferred scene-command buffer
    // to systems via `@Resource()`. The integration wires flutter_scene in; it
    // does not wrap it — systems configure skybox/environment/lighting/etc. directly
    // on `@Resource() Scene`.
    app.world.resources
      ..insert<Scene>(scene)
      ..insert<SceneCommands>(sceneCommands)
      ..insert<SceneNodeIndex>(SceneNodeIndex(_nodeIndex));
    // Standard integration system (renderSync): sync the standard SceneTransform
    // onto bound nodes after the gameplay `update` phase. Node mounting is *not*
    // a renderSync system — it runs before `update` (see _mountStep) so gameplay
    // sees mounted nodes — so a `@Bundle` can create its own node and simply
    // become visible.
    app.addSystemAdapter(
      SyncSceneNodesAdapter<SceneTransform>.full(
        (transform, target) => target.setFromTranslationRotationScale(
          transform.translation,
          transform.rotation,
          transform.scale,
        ),
      ),
      schedule: Schedules.renderSync,
      label: const SystemLabel('scene.syncTransform'),
    );
    app.start();
    // The mount adapter is not scheduled, so initialize it explicitly now that
    // stores exist, then mount any nodes spawned by startup systems and flush so
    // they are parented before the first frame's fixed/update steps run.
    _mountAdapter.initialize(app.world);
    _mountStep();
    final driver = EcsSceneDriver(_loop);
    scene.root.addComponent(driver);
    _driver = driver;
    _started = true;
  }

  /// `SceneView.onTick` handler: runs frame-start work.
  void onTick(Duration elapsed, double deltaSeconds) {
    _loop.frameStart(elapsed, deltaSeconds);
  }

  /// Shuts down the underlying app and detaches the internal scene driver.
  Future<void> shutdown() async {
    if (!_started || _shutdown) return;
    _shutdown = true;
    await app.shutdown();
    final driver = _driver;
    if (driver != null) {
      scene.root.removeComponent(driver);
      _driver = null;
    }
    sceneCommands.flush();
  }
}
