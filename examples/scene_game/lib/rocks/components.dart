part of 'rocks.dart';

/// Tags a rolling rock entity.
@Tag()
final class Rock {
  const Rock();
}

/// Tags the faster, on-fire rocks. Used both for their material and to drive the
/// shared [RockTrails] instanced trail (only flaming rocks get puffs).
@Tag()
final class Flaming {
  const Flaming();
}
