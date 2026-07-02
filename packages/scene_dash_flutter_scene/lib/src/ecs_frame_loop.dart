import 'package:scene_dash/scene_dash.dart';

/// Scene-free frame dispatcher: maps `flutter_scene` lifecycle callbacks onto
/// Scene-Dash schedules and updates the time resources.
///
/// Kept independent of `flutter_scene` so the frame/fixed/update dispatch is
/// unit-testable without a live `Scene` or GPU. [Game] and the internal scene
/// driver both delegate here.
final class EcsFrameLoop {
  /// The engine this loop drives.
  final App app;

  /// Optional hook called at the start of [update], before the `update`
  /// schedule. [Game] does not use it — mounting happens at every command
  /// boundary instead (see [onCommandBoundary]) — but custom drivers can hook
  /// pre-update work here.
  final void Function()? onBeforeUpdate;

  /// Called after a schedule has run and flushed ECS commands — after
  /// [frameStart], after each [fixedStep], and after the `update` schedule.
  /// [Game] mounts newly bound scene nodes here, so nodes spawned by any
  /// schedule are parented by the time the next schedule runs (in particular,
  /// gameplay `update` systems always see already-mounted nodes).
  final void Function()? onCommandBoundary;

  /// Called at the end of [update] (after `renderSync`, before the scene
  /// renders) — a safe boundary to flush deferred scene-graph mutations.
  final void Function()? onFrameEnd;

  EcsFrameLoop(
    this.app, {
    this.onBeforeUpdate,
    this.onCommandBoundary,
    this.onFrameEnd,
  });

  /// Inserts default [FrameTime]/[FixedTime] resources if a plugin has not
  /// already provided them. Call before [App.start].
  void ensureTimeResources() {
    final resources = app.world.resources;
    if (!resources.contains<FrameTime>()) resources.insert(FrameTime());
    if (!resources.contains<FixedTime>()) resources.insert(FixedTime());
  }

  /// Frame start: update [FrameTime], run [Schedules.frameStart], then advance
  /// event channels for the new frame.
  void frameStart(Duration elapsed, double deltaSeconds) {
    // Advance the profiler frame counter (if profiling is enabled) at the one
    // per-frame boundary, so timings can be attributed to a frame number.
    app.profiler?.beginFrame();
    app.world.resources.get<FrameTime>()
      ..delta = deltaSeconds
      ..elapsed = elapsed
      ..frame += 1;
    app.runSchedule(Schedules.frameStart);
    onCommandBoundary?.call();
    app.updateEvents();
  }

  /// Fixed step (before the scene physics step): update [FixedTime] and run
  /// [Schedules.fixedPrePhysics]. May run several times per frame.
  void fixedStep(double fixedDt) {
    app.world.resources.get<FixedTime>()
      ..delta = fixedDt
      ..tick += 1;
    app.runSchedule(Schedules.fixedPrePhysics);
    onCommandBoundary?.call();
  }

  /// Per-frame update: [onBeforeUpdate], then [Schedules.update], then
  /// [onCommandBoundary] (where [Game] mounts nodes spawned during `update`),
  /// [Schedules.renderSync], and finally [onFrameEnd] (e.g. flush scene-graph
  /// mutations) before render.
  void update(double deltaSeconds) {
    app.world.resources.get<FrameTime>().delta = deltaSeconds;
    onBeforeUpdate?.call();
    app.runSchedule(Schedules.update);
    onCommandBoundary?.call();
    app.runSchedule(Schedules.renderSync);
    onFrameEnd?.call();
  }
}
