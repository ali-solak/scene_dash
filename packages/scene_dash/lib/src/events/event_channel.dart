/// The non-generic maintenance surface of an [EventChannel].
///
/// The world stores channels behind this interface so it can advance them each
/// frame with a direct (non-dynamic) call regardless of their event type.
abstract interface class EventChannelMaintenance {
  /// Reclaims consumed events; see [EventChannel.update].
  ///
  /// Returns the largest number of unread events any single reader lost to
  /// the retention window this pass (`0` when no reader fell behind).
  int update();
}

/// A buffered, multi-reader event channel for events of type [T].
///
/// Events are appended by writers and read by any number of [EventReader]s,
/// each of which keeps its own independent cursor. One reader consuming events
/// never advances another reader's cursor.
///
/// [update] reclaims the prefix of events that every registered reader has
/// already observed, so the buffer does not grow without bound.
///
/// ## Retention
///
/// A reader that stops draining (a system that early-returns while the game is
/// paused, for example) would otherwise pin the buffer forever. Each event is
/// therefore kept for at most [retainedUpdates] maintenance passes: readers
/// that lag further behind skip the dropped events instead of leaking memory.
/// With the default of `2` and one [update] per frame, an event sent during
/// frame `N` stays readable through frames `N` and `N + 1` — the same window
/// Bevy's double-buffered events provide. Systems that read their channels
/// every frame never miss anything. Pass `null` to retain events until every
/// reader has consumed them, however long that takes.
final class EventChannel<T> implements EventChannelMaintenance {
  /// Creates a channel that keeps unread events for at most [retainedUpdates]
  /// calls to [update], or indefinitely when [retainedUpdates] is `null`.
  EventChannel({this.retainedUpdates = 2})
    : assert(
        retainedUpdates == null || retainedUpdates >= 1,
        'retainedUpdates must be at least 1 (or null for unbounded).',
      );

  /// How many maintenance passes an unread event survives, or `null` for
  /// unbounded retention.
  final int? retainedUpdates;

  final List<T> _events = <T>[];

  /// Absolute index of `_events[0]` in the channel's lifetime numbering.
  int _base = 0;

  final List<EventReader<T>> _readers = <EventReader<T>>[];

  /// The channel end (`_end`) recorded at each of the last
  /// `retainedUpdates - 1` maintenance passes, oldest first. Empty when
  /// retention is unbounded (or the window is a single pass).
  final List<int> _retainedEnds = <int>[];

  /// Absolute index just past the last event (one more than the newest).
  int get _end => _base + _events.length;

  /// Appends an event to the channel.
  void send(T event) => _events.add(event);

  /// Creates a reader positioned at the current end (it will only observe
  /// events sent after this call).
  EventReader<T> reader() {
    final reader = EventReader<T>._(this).._cursor = _end;
    _readers.add(reader);
    return reader;
  }

  /// Creates a writer bound to this channel.
  EventWriter<T> writer() => EventWriter<T>._(this);

  /// Drops the prefix of events that all readers have already consumed, and
  /// force-expires events older than the retention window (see [EventChannel]
  /// docs) so a stalled reader cannot pin the buffer.
  ///
  /// If there are no readers, every event is dropped.
  ///
  /// Returns the largest number of unread events any single reader lost to
  /// the retention window this pass (`0` when nobody fell behind), so the app
  /// can surface a diagnostic for readers that skip frames.
  @override
  int update() {
    if (_readers.isEmpty) {
      _base = _end;
      _events.clear();
      _retainedEnds.clear();
      return 0;
    }
    final maxPasses = retainedUpdates;
    var floor = _base;
    if (maxPasses != null) {
      // Events recorded [maxPasses - 1] passes ago have now been observable
      // for maxPasses frame windows; expire them. With maxPasses == 1 that is
      // everything sent before this pass.
      final window = maxPasses - 1;
      if (window == 0) {
        floor = _end;
      } else {
        if (_retainedEnds.length == window) {
          floor = _retainedEnds.removeAt(0);
        }
        _retainedEnds.add(_end);
      }
    }
    var minCursor = _end;
    var maxSkipped = 0;
    for (final reader in _readers) {
      // A reader that lagged past the retention window misses the expired
      // events; its cursor jumps forward so the prefix can be reclaimed.
      final lag = floor - reader._cursor;
      if (lag > 0) {
        reader._cursor = floor;
        if (lag > maxSkipped) maxSkipped = lag;
      }
      if (reader._cursor < minCursor) minCursor = reader._cursor;
    }
    final drop = minCursor - _base;
    if (drop > 0) {
      _events.removeRange(0, drop);
      _base += drop;
    }
    return maxSkipped;
  }
}

/// A cursor-based reader over an [EventChannel].
///
/// Each call to [drain] returns the events sent since the previous call and
/// advances this reader's cursor to the channel's current end.
final class EventReader<T> {
  final EventChannel<T> _channel;
  int _cursor = 0;

  EventReader._(this._channel);

  /// Whether unread events are available for this reader.
  bool get hasUnread => _cursor < _channel._end;

  /// Invokes [callback] for every unread event without allocating a result
  /// list, then advances this reader's cursor.
  ///
  /// If [callback] throws, the cursor is left unchanged so the unread events can
  /// be retried.
  void forEach(void Function(T event) callback) {
    final from = _cursor - _channel._base;
    final start = from < 0 ? 0 : from;
    final end = _channel._events.length;
    for (var i = start; i < end; i++) {
      callback(_channel._events[i]);
    }
    _cursor = _channel._end;
  }

  /// Returns and consumes all events this reader has not yet seen.
  ///
  /// Allocates the returned list; prefer [forEach] in per-frame systems.
  List<T> drain() {
    final from = _cursor - _channel._base;
    final start = from < 0 ? 0 : from;
    final result = _channel._events.sublist(start);
    _cursor = _channel._end;
    return result;
  }
}

/// A handle that appends events to an [EventChannel].
final class EventWriter<T> {
  final EventChannel<T> _channel;

  EventWriter._(this._channel);

  /// Sends [event] to all readers of the channel.
  void send(T event) => _channel.send(event);
}
