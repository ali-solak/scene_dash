part of 'rules.dart';

/// Evaluates the two lose conditions each frame, as a top-level `@System`
/// function with an injected `Single<SceneNodeRef>` player (generates an
/// `evaluateGameRulesSystem` descriptor).
///
/// Fell off: a downward raycast finds no fixed platform within
/// [groundProbeDistance]. Hit by a rock: any rock is within the combined radii
/// of the player.
@System()
void evaluateGameRules(
  @Query(requires: [Player]) Single<SceneNodeRef> player,
  @Resource() PhysicsWorld world,
  @Resource() GameState game,
  @Resource() FrameTime time,
  @Resource() ImpactMotion impact,
) {
  if (game.status != GameStatus.playing) return;

  // The single player always exists (spawned at startup, never despawned) and
  // the integration mounts its node before update, so it is already in scene.
  final node = player.value.node;
  final pos = node.globalTransform.getTranslation();

  game.addSurvival(time.delta);

  if (game.survived > startupGrace) {
    final ground = world.raycast(
      Ray.originDirection(pos, Vector3(0, -1, 0)),
      maxDistance: groundProbeDistance,
      includeFixed: true,
      includeKinematic: false,
      includeDynamic: false,
    );
    if (ground == null) {
      game.lose('You fell off the platform');
      return;
    }
  }

  final hits = world.overlapSphere(
    pos,
    playerRadius + hitPadding,
    layerMask: PhysicsLayers.rock,
    includeFixed: false,
    includeKinematic: false,
    includeDynamic: true,
    includeTriggers: false,
  );
  for (final hit in hits) {
    // overlapSphere's layerMask is not yet honored by flutter_scene_rapier, so
    // classify rocks on the result side by collider layer - a handful of hits,
    // not a rebuilt Set of every rock each frame.
    final collider = hit.collider;
    if (collider is! RapierCollider ||
        collider.collisionLayer & PhysicsLayers.rock == 0) {
      continue;
    }
    _startImpact(node, pos, hit.node.globalTransform.getTranslation(), impact);
    game.lose('A rock got you');
    return;
  }
}

void _startImpact(
  Node player,
  Vector3 playerPos,
  Vector3 rockPos,
  ImpactMotion impact,
) {
  final body = player.getComponent<RapierRigidBody>();
  if (body != null) {
    body
      ..type = BodyType.kinematic
      ..linearVelocity = Vector3.zero()
      ..angularVelocity = Vector3.zero();
  }
  impact.start(playerPosition: playerPos, rockPosition: rockPos);
}

/// Keeps camera state current and runs the visible post-hit tumble.
@System()
final class PlayerViewSystem extends GameSystem {
  const PlayerViewSystem();

  void run(
    @Query(requires: [Player]) Single<SceneNodeRef> player,
    @Resource() CameraRig camera,
    @Resource() ImpactMotion impact,
    @Resource() FrameTime time,
  ) {
    final node = player.value.node;
    final pos = node.globalTransform.getTranslation();

    if (impact.active) {
      impact.advance(time.delta);
      node.localTransform = impact.transform();
      camera.follow(impact.position, time.delta);
      return;
    }

    camera.follow(pos, time.delta);
  }
}

/// Restarts after a loss by clearing rocks and restoring the player body.
@System()
final class RestartSystem extends GameSystem {
  const RestartSystem();

  void run(
    @Query(requires: [Player]) Query1<SceneNodeRef> players,
    @Query(requires: [Rock]) Query1<SceneNodeRef> rocks,
    @Resource() InputState input,
    @Resource() GameState game,
    @Resource() RockSpawner spawner,
    @Resource() CameraRig camera,
    @Resource() ImpactMotion impact,
    Commands commands,
  ) {
    if (!input.restartRequested) return;
    input.restartRequested = false;
    if (game.status != GameStatus.lost) return;

    rocks.each((entity, binding) => commands.despawn(entity));
    players.each((entity, binding) {
      final body = binding.node.getComponent<RapierRigidBody>();
      if (body != null) {
        body
          ..type = BodyType.kinematic
          ..linearVelocity = Vector3.zero()
          ..angularVelocity = Vector3.zero();
      }
      binding.node.localTransform = Matrix4.translation(
        Vector3(0, playerStartY, playerStartZ),
      );
    });
    camera.reset();
    impact.reset();
    spawner.reset();
    game.reset();
  }
}
