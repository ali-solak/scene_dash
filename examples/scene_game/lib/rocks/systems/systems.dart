part of '../rocks.dart';

/// Fixed step: drop new rocks at the top while the game is running.
@System()
final class SpawnRocksSystem extends GameSystem {
  const SpawnRocksSystem();

  void run(
    Commands commands,
    @Resource() RockSpawner spawner,
    @Resource() GameState game,
    @Resource() FixedTime time,
  ) {
    final due = spawner.tick(time.delta, survived: game.survived);
    for (var i = 0; i < due; i++) {
      final x = spawner.nextLane();
      final flaming = spawner.nextIsFlaming(game.survived);
      final entity = commands.spawn(RockBundle(x: x, flaming: flaming));
      // Flaming rocks get a tag; their trail puffs are drawn from the shared
      // RockTrails instanced pool by updateRockTrails.
      if (flaming) commands.insert<Flaming>(entity, const Flaming());
    }
  }
}

/// Despawns rocks that have rolled off the bottom into the void.
@System()
final class CleanupRocksSystem extends GameSystem {
  const CleanupRocksSystem();

  void run(
    @Query(requires: [Rock]) Query1<SceneNodeRef> rocks,
    Commands commands,
  ) {
    rocks.each((entity, binding) {
      // The integration mounts bound nodes before the update phase, so a queried
      // rock is already in the scene - no parent guard needed.
      if (binding.node.globalTransform.getTranslation().y < rockKillY) {
        commands.despawn(entity);
      }
    });
  }
}

/// Update: animate the per-rock flash shell for rocks with an active hit
/// reaction, then drop the reaction component when the flash finishes.
///
/// The native body bounce/spin (applied by the projectile hit) is the physical
/// reaction; this child shell is the visual one — the physics-driven root node
/// is never scaled. The shell grows from nothing to a strength-scaled peak and
/// collapses back, with a couple of pulses on the way. It mutates the shell
/// node's own transform matrix in place (re-assigning to trip the dirty flag),
/// so it allocates nothing per frame.
@System()
void updateRockHitReactions(
  @Query(requires: [Rock], writes: [RockHitReaction, RockVisuals])
  Query2<RockHitReaction, RockVisuals> reactions,
  @Resource() FrameTime time,
  Commands commands,
) {
  final dt = time.delta;
  reactions.each((entity, reaction, visuals) {
    reaction.remaining -= dt;
    final shell = visuals.shell;
    if (reaction.remaining <= 0) {
      _setShellScale(shell, 0);
      commands.remove<RockHitReaction>(entity);
      return;
    }
    final t = (1 - reaction.remaining / rockHitReactionDuration).clamp(0.0, 1.0);
    // Grow-then-collapse envelope (0 -> 1 -> 0) so the shell appears and clears
    // cleanly; a few ripples and a strength-scaled peak read the hit's force.
    final env = math.sin(t * math.pi);
    final pulse = 1 + 0.1 * math.sin(t * math.pi * 4);
    final peak = 1.15 + 0.55 * reaction.strength;
    _setShellScale(shell, peak * env * pulse);
  });
}

/// Writes a uniform [scale] onto [shell] by mutating its own transform matrix in
/// place and re-assigning it (to trip the node's dirty flag) — no allocation.
void _setShellScale(Node shell, double scale) {
  final m = shell.localTransform
    ..setIdentity()
    ..scaleByDouble(scale, scale, scale, 1);
  shell.localTransform = m;
}

/// Startup: build the shared flame-trail pool and add its node to the scene.
@System()
void spawnRockTrails(@Resource() Scene scene, @Resource() RockTrails trails) {
  trails.pool = buildFlamePool()..addTo(scene);
}

/// Update: lay each live flaming rock's puffs into the shared instanced pool by
/// enumeration order, then hide the slots freed by despawned rocks. One pool
/// node under the scene root draws every trail in a single call. Flaming rocks
/// roll down +Z, so the puffs trail a fixed distance behind in -Z (no per-rock
/// state). Allocation-free: reads the transform's translation columns directly
/// and reuses one scratch matrix.
@System()
void updateRockTrails(
  @Query(requires: [Rock, Flaming]) Query1<SceneNodeRef> rocks,
  @Resource() RockTrails trails,
) {
  final pool = trails.pool;
  if (pool == null) return;
  final scratch = pool.scratch;
  var slot = 0;

  rocks.each((entity, binding) {
    if (slot + _puffsPerRock > pool.capacity) return; // pool full
    final m = binding.node.globalTransform;
    for (var i = 0; i < _puffsPerRock; i++) {
      final size = rockRadius * (0.34 - i * 0.07);
      scratch
        ..setIdentity()
        ..setTranslationRaw(
          m[12],
          m[13] + rockRadius * (0.12 + 0.08 * i),
          m[14] - rockRadius * 0.55 * (i + 1),
        )
        ..scaleByDouble(size, size, size, 1);
      pool.mesh.setInstanceTransform(slot, scratch);
      slot++;
    }
  });

  // Hide instances that belonged to rocks which despawned since last frame.
  for (var i = slot; i < trails.activeCount; i++) {
    pool.hide(i);
  }
  trails.activeCount = slot;
}
