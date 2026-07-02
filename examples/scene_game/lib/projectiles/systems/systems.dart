part of '../projectiles.dart';

/// Per-frame scratch for the live projectile position, reused so the update
/// loop allocates nothing per projectile.
final Vector3 _projectilePosition = Vector3.zero();

@System()
final class ShootProjectilesSystem extends GameSystem {
  const ShootProjectilesSystem();

  void run(
    Commands commands,
    // Reads the player position only (no node mutation), so no `writes:` here.
    @Query(requires: [Player]) Single<SceneNodeRef> player,
    @Resource() InputState input,
    @Resource() GameState game,
    @Resource() Blaster blaster,
    @Resource() LockOnReticle reticle,
    @Resource() FixedTime time,
  ) {
    if (game.status != GameStatus.playing) {
      blaster.reset();
      input.clearFireTransitions();
      return;
    }

    final shots = blaster.update(
      pressed: input.firePressed,
      released: input.fireReleased,
      canceled: input.fireCanceled,
      held: input.fireHeld,
      dt: time.delta,
    );
    input.clearFireTransitions();
    if (shots.isEmpty) return;

    final base = player.value.node.globalTransform.getTranslation()
      ..y += playerBodyVisualRadius * 0.45
      ..z -= playerBodyVisualRadius + projectileRadius + 0.08;

    final charged = shots.charged;
    if (charged != null) {
      // A charged release is one larger projectile, not a burst.
      final strength = math.max(charged, minChargedCharge);
      commands.spawn(ProjectileBundle(position: base, charge: strength));
      reticle.flashFired();
    } else {
      for (var i = 0; i < shots.burst; i++) {
        commands.spawn(ProjectileBundle(position: base));
      }
    }
  }
}

@System()
final class UpdateProjectilesSystem extends GameSystem {
  const UpdateProjectilesSystem();

  void run(
    @Query(writes: [Projectile]) Query2<Projectile, SceneNodeRef> projectiles,
    @Resource() PhysicsWorld physics,
    @Resource() SceneNodeIndex index,
    @Resource() ImpactVfx vfx,
    @Resource() LockOnReticle reticle,
    @Resource() FrameTime time,
    Commands commands,
  ) {
    final dt = time.delta;
    projectiles.each((entity, projectile, binding) {
      projectile.age += dt;
      // globalTransform returns the node's cached matrix (no allocation); read
      // the translation from its column-major storage into the reused scratch.
      // _knockRocks consumes it before the next iteration overwrites it.
      final m = binding.node.globalTransform.storage;
      final position = _projectilePosition..setValues(m[12], m[13], m[14]);

      if (projectile.age >= projectileLifetime ||
          position.z < -rampLength * 0.5 - 2 ||
          position.y < -2) {
        commands.despawn(entity);
        return;
      }

      final hitCount = _knockRocks(
        physics,
        index,
        commands,
        vfx,
        position,
        projectile,
      );
      if (hitCount > 0) {
        reticle.flashImpact();
        if (!projectile.charged ||
            projectile.hitRocks.length >= chargedProjectileMaxHits) {
          commands.despawn(entity);
        }
      }
    });
  }

  /// Applies the native bounce/spin to the first rock overlapping [position],
  /// scaled by [charge], and inserts an ECS hit reaction on the resolved rock
  /// entity. Returns whether a rock was hit.
  int _knockRocks(
    PhysicsWorld physics,
    SceneNodeIndex index,
    Commands commands,
    ImpactVfx vfx,
    Vector3 position,
    Projectile projectile,
  ) {
    final hits = physics.overlapSphere(
      position,
      projectileHitRadiusForCharge(projectile.charge),
      layerMask: PhysicsLayers.rock,
      includeFixed: false,
      includeKinematic: false,
      includeDynamic: true,
      includeTriggers: false,
    );
    var hitCount = 0;
    for (final hit in hits) {
      final collider = hit.collider;
      if (collider is! RapierCollider ||
          collider.collisionLayer & PhysicsLayers.rock == 0) {
        continue;
      }

      final entity = index.entityOf(hit.node);
      if (projectile.charged) {
        if (entity == null || projectile.hitRocks.contains(entity.index)) {
          continue;
        }
      }

      final rockPosition = hit.node.globalTransform.getTranslation();
      final xAway = rockPosition.x - position.x;
      final knock = projectileKnockbackForCharge(projectile.charge);
      final lift = projectileLiftForCharge(projectile.charge);
      final spin = projectileSpinForCharge(projectile.charge);
      hit.node.getComponent<RapierRigidBody>()
        ?..linearVelocity = Vector3(
          xAway.clamp(-1, 1).toDouble() * knock * 0.35,
          lift,
          -knock,
        )
        ..angularVelocity = Vector3(-spin, 0, xAway.sign * spin * 0.55);

      // Resolve the hit node back to its rock entity (the index walks ancestors,
      // so a hit on a child mesh still resolves) and attach a scaled hit
      // reaction — no rebuilt node/entity maps, no scan of all rocks.
      if (entity != null) {
        if (projectile.charged) projectile.hitRocks.add(entity.index);
        commands.insert<RockHitReaction>(
          entity,
          RockHitReaction(
            strength: projectile.charge.clamp(0.0, 1.0).toDouble(),
          ),
        );
      }
      vfx.emit(rockPosition, strength: projectile.charge);
      hitCount++;
      if (!projectile.charged || hitCount >= chargedProjectileMaxHits) break;
    }
    return hitCount;
  }
}

// --- Shared helpers used across the projectile parts (charge VFX, reticle) ---

/// Eases [value] a fraction [rate] (0..1) of the way toward [target]; a simple
/// frame-rate-scaled lerp used for charge, opacity and show factors.
double _approach(double value, double target, double rate) {
  final a = rate.clamp(0.0, 1.0);
  return value + (target - value) * a;
}

/// Writes a uniform-scaled local transform at (x,y,z) onto [node] in place.
void _placeUniform(Node node, double x, double y, double z, double s) =>
    _place(node, x, y, z, s, s, s);

/// Writes a local transform at (x,y,z) with per-axis scale onto [node] in place.
void _place(
  Node node,
  double x,
  double y,
  double z,
  double sx,
  double sy,
  double sz,
) {
  final m = node.localTransform
    ..setIdentity()
    ..setTranslationRaw(x, y, z)
    ..scaleByDouble(sx, sy, sz, 1);
  node.localTransform = m;
}
