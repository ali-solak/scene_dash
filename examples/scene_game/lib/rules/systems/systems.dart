part of '../rules.dart';

// Per-frame scratch state, reused so rule evaluation and the camera follow
// allocate nothing per frame. Systems run sequentially, so sharing is safe.
final Vector3 _playerPos = Vector3.zero();
final Vector3 _rockPos = Vector3.zero();

/// Reusable downward ground probe; only its origin changes per frame.
final Ray _groundRay = Ray.originDirection(Vector3.zero(), Vector3(0, -1, 0));

/// Evaluates the lose condition and rock contacts each frame, as a top-level
/// `@System`
/// function with an injected `Single<SceneNodeRef>` player (generates an
/// `evaluateGameRulesSystem` descriptor).
///
/// Fell off: a downward raycast finds no fixed platform within
/// [groundProbeDistance]. Hit by a rock: request player-owned knockback instead
/// of ending the run immediately.
@System()
void evaluateGameRules(
  @Query(requires: [Player]) Single<SceneNodeRef> player,
  @Resource() PhysicsWorld world,
  @Resource() GameState game,
  @Resource() FrameTime time,
  @Resource() PlayerKnockback knockback,
  @Resource() ShieldState shield,
  @Resource() ShieldDeflectVfx deflectVfx,
) {
  // The single player always exists (spawned at startup, never despawned) and
  // the integration mounts its node before update, so it is already in scene.
  final node = player.value.node;
  // globalTransform returns the node's cached matrix (no allocation); read the
  // translation out of its column-major storage into the reused scratch.
  final m = node.globalTransform.storage;
  final pos = _playerPos..setValues(m[12], m[13], m[14]);

  game.addSurvival(time.delta);

  if (game.survived > startupGrace) {
    _groundRay.origin.setFrom(pos);
    final ground = world.raycast(
      _groundRay,
      maxDistance: groundProbeDistance,
      includeFixed: true,
      includeKinematic: false,
      includeDynamic: false,
    );
    if (ground == null && pos.y <= playerFallLoseY) {
      game.lose('You fell off the platform');
      return;
    }
  }

  final hits = world.overlapSphere(
    pos,
    playerCollisionRadius + hitPadding,
    layerMask: PhysicsLayers.rock,
    includeFixed: false,
    includeKinematic: false,
    includeDynamic: true,
    includeTriggers: false,
  );
  // Capture the shield state once for the whole resolution pass: if it was up
  // when contacts were evaluated, it protects against every rock this frame,
  // even once deflecting one drains the timer to zero.
  final shielded = shield.active;
  for (final hit in hits) {
    // overlapSphere's layerMask is not yet honored by flutter_scene_rapier, so
    // classify rocks on the result side by collider layer - a handful of hits,
    // not a rebuilt Set of every rock each frame.
    final collider = hit.collider;
    if (collider is! RapierCollider ||
        collider.collisionLayer & PhysicsLayers.rock == 0) {
      continue;
    }
    final rm = hit.node.globalTransform.storage;
    final rockPos = _rockPos..setValues(rm[12], rm[13], rm[14]);
    if (shielded) {
      _deflectRock(hit.node, pos, rockPos, deflectVfx);
      shield.absorbHit();
      continue;
    }
    knockback.pushFromRock(playerPosition: pos, rockPosition: rockPos);
    return;
  }
}

/// Throws a rock up and away from the player, with a stable direction even when
/// the centres overlap. Bounded by the deflection constants in config.
void _deflectRock(
  Node rockNode,
  Vector3 playerPos,
  Vector3 rockPos,
  ShieldDeflectVfx vfx,
) {
  var dx = rockPos.x - playerPos.x;
  var dz = rockPos.z - playerPos.z;
  var len = math.sqrt(dx * dx + dz * dz);
  if (len < 1e-4) {
    // Centres overlap: push uphill (-Z) by default rather than dividing by zero.
    dx = 0;
    dz = -1;
    len = 1;
  }
  final nx = dx / len;
  final nz = dz / len;
  final body = rockNode.getComponent<RapierRigidBody>();
  if (body != null) {
    body
      ..linearVelocity = Vector3(
        nx * shieldDeflectOutward,
        shieldDeflectUp,
        nz * shieldDeflectOutward,
      )
      ..angularVelocity = Vector3(
        shieldDeflectSpin,
        0,
        nx.sign * shieldDeflectSpin,
      );
  }
  vfx.emit(rockPos);
}

/// Keeps camera state current after movement and rule evaluation.
@System()
final class PlayerViewSystem extends GameSystem {
  const PlayerViewSystem();

  void run(
    @Query(requires: [Player]) Single<SceneNodeRef> player,
    @Resource() CameraRig camera,
    @Resource() FrameTime time,
  ) {
    final m = player.value.node.globalTransform.storage;
    camera.follow(_playerPos..setValues(m[12], m[13], m[14]), time.delta);
  }
}

/// Restarts after a loss: clears rocks, projectiles and pickups, restores the
/// player body, and resets all feature state (blaster, shield, spawners, VFX and
/// fire input) so a new run starts clean.
@System()
final class RestartSystem extends GameSystem {
  const RestartSystem();

  void run(
    @Query(requires: [Player], writes: [SceneNodeRef])
    Single<SceneNodeRef> player,
    @Query(requires: [Player], writes: [PlayerVisuals])
    Single<PlayerVisuals> playerVisuals,
    @Query(requires: [Rock]) Query1<SceneNodeRef> rocks,
    @Query(requires: [Projectile]) Query1<SceneNodeRef> projectiles,
    @Query(requires: [Collectable]) Query1<SceneNodeRef> pickups,
    @Resource() InputState input,
    @Resource() GameState game,
    @Resource() RockSpawner spawner,
    @Resource() CameraRig camera,
    @Resource() PlayerKnockback knockback,
    @Resource() Blaster blaster,
    @Resource() ImpactVfx impactVfx,
    @Resource() LockOnReticle reticle,
    @Resource() ShieldState shield,
    @Resource() CollectableSpawner pickupSpawner,
    @Resource() ShieldDeflectVfx deflectVfx,
    Commands commands,
  ) {
    if (!input.restartRequested) return;
    input.restartRequested = false;
    if (game.status != GameStatus.lost) return;

    rocks.each((entity, binding) => commands.despawn(entity));
    projectiles.each((entity, binding) => commands.despawn(entity));
    pickups.each((entity, binding) => commands.despawn(entity));

    // Restoring the player resets its native body and transform (reached
    // through SceneNodeRef), hence `writes: [SceneNodeRef]` above.
    final ref = player.value;
    final node = ref.node;
    final body = ref.component<RapierRigidBody>();
    if (body != null) {
      body
        ..type = BodyType.kinematic
        ..linearVelocity = Vector3.zero()
        ..angularVelocity = Vector3.zero();
    }
    node.localTransform = Matrix4.translation(
      Vector3(0, playerStartY, playerStartZ),
    );
    camera.reset();
    knockback.reset();
    spawner.reset();
    blaster.reset();
    impactVfx.reset();
    reticle.reset();
    shield.reset();
    pickupSpawner.reset();
    deflectVfx.reset();
    input.clearFireTransitions();
    playerVisuals.value.resetLegs();
    game.reset();
    // Player charge/shield visuals self-clear: their systems ease the orb and
    // bubble out once the blaster is reset and the shield is inactive.
  }
}
