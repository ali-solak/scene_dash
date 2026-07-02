part of '../collectables.dart';

/// Fixed step: spawn a shield pickup at the high end of the ramp when none is
/// active and the cadence is due. The [OptionalSingle] gate is the single source
/// of "is a pickup active" — no duplicate boolean or entity id in the spawner.
@System()
void spawnShieldPickups(
  @Query(requires: [ShieldPickup]) OptionalSingle<SceneNodeRef> activePickup,
  @Resource() CollectableSpawner spawner,
  @Resource() FixedTime time,
  Commands commands,
) {
  if (activePickup.isPresent) return; // keep at most one pickup
  if (!spawner.tick(time.delta)) return;
  commands.spawn(ShieldPickupBundle(x: spawner.nextLane()));
}

/// Update: count the active shield down while the run is going.
@System()
void updateShieldState(
  @Resource() ShieldState shield,
  @Resource() FrameTime time,
) {
  shield.tick(time.delta);
}

/// Update: pulse and bob each pickup's glow child. The physics-driven root
/// transform is left to Rapier (the pickup visibly rolls down the ramp); only
/// the glow child is animated, in place, with no allocation.
@System()
void animateShieldPickups(
  @Query(
    requires: [ShieldPickup],
    writes: [ShieldPickupState, ShieldPickupVisuals],
  )
  Query2<ShieldPickupState, ShieldPickupVisuals> pickups,
  @Resource() FrameTime time,
) {
  final dt = time.delta;
  pickups.each((entity, state, visuals) {
    state.age += dt;
    final pulse = 1 + 0.18 * math.sin(state.age * 6);
    final bob = 0.12 * math.sin(state.age * 3);
    final glow = visuals.glow;
    final m = glow.localTransform
      ..setIdentity()
      ..setTranslationRaw(0, bob, 0)
      ..scaleByDouble(pulse, pulse, pulse, 1);
    glow.localTransform = m;
  });
}

/// Update: collect a pickup when the player is close enough. A direct squared
/// distance is appropriate because only zero or one pickup exists. On
/// collection the shield activates/refreshes (the pop feedback is driven by the
/// shield VFX system on the activation edge) and the pickup despawns.
@System()
void collectShieldPickups(
  @Query(requires: [Player]) Single<SceneNodeRef> player,
  @Query(requires: [ShieldPickup]) Query1<SceneNodeRef> pickups,
  @Resource() ShieldState shield,
  Commands commands,
) {
  final p = player.value.node.globalTransform.getTranslation();
  pickups.each((entity, binding) {
    final c = binding.node.globalTransform.getTranslation();
    final dx = c.x - p.x;
    final dy = c.y - p.y;
    final dz = c.z - p.z;
    if (dx * dx + dy * dy + dz * dz <= shieldCollectDistanceSq) {
      shield.activate();
      commands.despawn(entity);
    }
  });
}

/// Update: drive the player's shield bubble and activation badge from
/// [ShieldState] (which owns the timing). On the activation edge a badge pops in
/// front of the player with an overshoot, then the bubble grows around the
/// player; during the warning window the pulse speeds up and the bubble flashes;
/// on expiry it shrinks and hides cleanly. Mutates player-owned nodes/materials
/// in place — no shared-material leaks, no per-frame allocation.
@System()
void updateShieldVisuals(
  @Query(requires: [Player], writes: [PlayerVisuals])
  Single<PlayerVisuals> visuals,
  @Resource() ShieldState shield,
  @Resource() FrameTime time,
) {
  final v = visuals.value;
  final dt = time.delta;

  // Activation pop on the inactive -> active edge.
  if (shield.active && !v.shieldWasActive) v.badgePop = 1;
  v.shieldWasActive = shield.active;

  final warning = shield.expiringSoon;
  v.shieldPhase += dt * (warning ? 16 : 4);
  final breathe = 1 + 0.05 * math.sin(v.shieldPhase);
  final warnFlash = warning ? 0.5 + 0.5 * math.sin(v.shieldPhase * 1.5) : 1.0;

  // Bubble: eased show factor so expiry shrinks it cleanly.
  v.shieldShow = _approach(v.shieldShow, shield.active ? 1.0 : 0.0, dt * 8);
  final bubbleScale = v.shieldShow * breathe;
  _placeUniform(v.shieldBubble, 0, 0, 0, bubbleScale);
  v.shieldBubbleMaterial.baseColorFactor = Vector4(
    0.4,
    0.8,
    1.0,
    (0.12 + 0.12 * warnFlash) * v.shieldShow,
  );
  v.shieldBubbleMaterial.emissiveFactor = Vector4(
    0.25 * warnFlash,
    0.6 * warnFlash,
    1.1 * warnFlash,
    1,
  );

  // Activation badge: a short overshoot in front of the player.
  v.badgePop = math.max(0, v.badgePop - dt / 0.45);
  final prog = 1 - v.badgePop;
  final badgeScale = v.badgePop > 0.001 ? math.sin(prog * math.pi) * 1.3 : 0.0;
  _placeUniform(
    v.shieldBadge,
    0,
    playerBodyVisualRadius * 0.6,
    -(playerBodyVisualRadius + 0.4),
    badgeScale,
  );
}

/// Update: despawn pickups that fell below the world or rolled past the ramp.
@System()
void cleanupPickups(
  @Query(requires: [Collectable]) Query1<SceneNodeRef> pickups,
  Commands commands,
) {
  pickups.each((entity, binding) {
    final pos = binding.node.globalTransform.getTranslation();
    if (pos.y < collectableKillY || pos.z > collectablePassZ) {
      commands.despawn(entity);
    }
  });
}

/// Startup: build the shared shield-deflection pool and add its node.
@System()
void spawnShieldDeflectVfx(
  @Resource() Scene scene,
  @Resource() ShieldDeflectVfx vfx,
) {
  vfx.pool = buildDeflectPool()..addTo(scene);
}

/// Update: advance the shield-deflection pool. Allocation-free — one scratch
/// matrix, reused for every instance.
@System()
void updateShieldDeflectVfx(
  @Resource() ShieldDeflectVfx vfx,
  @Resource() FrameTime time,
) {
  final pool = vfx.pool;
  if (pool == null) return;
  final dt = time.delta;
  final scratch = pool.scratch;
  for (var i = 0; i < vfx.age.length; i++) {
    final a = vfx.age[i];
    if (a >= _deflectDuration) continue;
    final next = a + dt;
    vfx.age[i] = next;
    final t = (next / _deflectDuration).clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - t, 2).toDouble();
    final fade = 1 - t;
    final s = (0.5 + 1.4 * ease) * fade;
    scratch
      ..setIdentity()
      ..setTranslationRaw(
        vfx.origin[i * 3],
        vfx.origin[i * 3 + 1] + 0.6 * ease,
        vfx.origin[i * 3 + 2],
      )
      ..scaleByDouble(s, s, s, 1);
    pool.mesh.setInstanceTransform(i, scratch);
  }
}

double _approach(double value, double target, double rate) {
  final a = rate.clamp(0.0, 1.0);
  return value + (target - value) * a;
}

/// Writes a uniform-scaled local transform at (x,y,z) onto [node] in place
/// (re-assigning to trip the dirty flag) — no allocation.
void _placeUniform(Node node, double x, double y, double z, double s) {
  final m = node.localTransform
    ..setIdentity()
    ..setTranslationRaw(x, y, z)
    ..scaleByDouble(s, s, s, 1);
  node.localTransform = m;
}
