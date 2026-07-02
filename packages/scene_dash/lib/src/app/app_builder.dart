import 'dart:async';

import '../schedule/schedule_label.dart';
import '../schedule/system_descriptor.dart';
import '../schedule/system_label.dart';
import '../schedule/system_registration.dart';
import '../system/system_adapter.dart';
import 'plugin.dart';

/// The registration surface handed to a [Plugin.build].
///
/// A plugin uses the builder to register systems, declare event channels,
/// insert resources and pull in dependency plugins. It deliberately does *not*
/// expose frame execution — that belongs to the app/scene driver.
abstract interface class AppBuilder {
  /// Registers a `@System` [descriptor] into [schedule], optionally constrained
  /// to run `after`/`before` other systems (referenced by their descriptors).
  ///
  /// [descriptor] is the generated `SystemDescriptor` for a `@System` class or
  /// function (e.g. `movePlayerSystem`); its identity and adapter come from the
  /// generator, so there is no hand-written label and no `with _$…` mixin.
  ///
  /// [runIf] gates each run: the condition is evaluated every schedule pass
  /// and the system is skipped while it returns `false`.
  AppBuilder addSystem(
    SystemDescriptor descriptor, {
    required ScheduleLabel schedule,
    List<SystemDescriptor> after,
    List<SystemDescriptor> before,
    RunCondition? runIf,
  });

  /// Registers a system [adapter] directly. Used by hand-written adapters
  /// (tests, advanced integrations) that do not go through a `@System` class.
  AppBuilder addSystemAdapter(
    SystemAdapter adapter, {
    required ScheduleLabel schedule,
    required SystemLabel label,
    List<SystemLabel> after,
    List<SystemLabel> before,
    RunCondition? runIf,
  });

  /// Declares an event channel for event type [T] (idempotent).
  ///
  /// [retainedUpdates] bounds how many event-maintenance passes (normally one
  /// per frame) an unread event survives, so a reader that stops draining
  /// cannot grow the buffer without bound. The default of `2` keeps an event
  /// readable for the frame it was sent plus the next one; pass `null` to
  /// retain events until every reader has consumed them.
  AppBuilder addEvent<T>({int? retainedUpdates});

  /// Inserts the resource instance for type [T].
  ///
  /// Throws [StateError] if a resource of type [T] is already present: each
  /// resource should be owned by exactly one place (the plugin that uses it, or
  /// a single insertion through the game for an externally-constructed
  /// dependency). Use [replaceResource] when swapping is intentional, so an
  /// accidental double-registration fails loudly instead of silently winning.
  AppBuilder insertResource<T extends Object>(T resource);

  /// Replaces (or inserts) the resource instance for type [T]. Use this when
  /// intentionally swapping a resource; [insertResource] rejects duplicates.
  AppBuilder replaceResource<T extends Object>(T resource);

  /// Registers cleanup to run once when the app shuts down.
  AppBuilder addCleanup(FutureOr<void> Function() cleanup);

  /// Builds [plugin] into this app if it has not already been added.
  AppBuilder addPlugin(Plugin plugin);
}
