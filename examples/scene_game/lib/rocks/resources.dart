part of 'rocks.dart';

/// Spawn cadence plus RNG, injected as a resource.
final class RockSpawner {
  final math.Random random;
  double _accumulator = 0;

  RockSpawner({int? seed}) : random = math.Random(seed);

  /// Advances the timer; returns the number of rocks due this step.
  int tick(double dt, {required double survived}) {
    _accumulator += dt;
    var due = 0;
    final interval = rockSpawnIntervalForSurvival(survived);
    while (_accumulator >= interval) {
      _accumulator -= interval;
      due++;
    }
    return due;
  }

  /// A random X within the ramp's spawn band.
  double nextLane() => (random.nextDouble() * 2 - 1) * rockSpawnHalfWidth;

  bool nextIsFlaming(double survived) {
    return random.nextDouble() < flamingRockChanceForSurvival(survived);
  }

  void reset() => _accumulator = 0;
}

/// Shared instanced pool for every flaming rock's trail puffs — one node, one
/// draw call for all trails instead of one [InstancedMesh] per rock. Built at
/// startup; the trail system assigns instance ranges to live flaming rocks each
/// frame and hides the leftovers.
final class RockTrails {
  /// Built by `spawnRockTrails`; null until then.
  InstancedPool? pool;

  /// Instances written last frame, so the next frame can hide the surplus when
  /// flaming rocks despawn.
  int activeCount = 0;
}
