import 'package:scene_dash/scene_dash.dart';
import 'package:test/test.dart';

final class Pinged {
  final int id;
  const Pinged(this.id);
}

void main() {
  group('EventChannel', () {
    test('a reader drains only events sent after it was created', () {
      final channel = EventChannel<Pinged>();
      channel.send(const Pinged(0)); // before reader exists
      final reader = channel.reader();
      channel.send(const Pinged(1));
      channel.send(const Pinged(2));

      expect(reader.drain().map((e) => e.id), <int>[1, 2]);
      expect(reader.drain(), isEmpty, reason: 'cursor advanced');
    });

    test('readers have independent cursors', () {
      final channel = EventChannel<Pinged>();
      final a = channel.reader();
      final b = channel.reader();

      channel.send(const Pinged(1));
      expect(a.drain().map((e) => e.id), <int>[1]);
      // b has not read yet, so it still sees the event.
      expect(b.drain().map((e) => e.id), <int>[1]);
    });

    test('update reclaims events all readers have consumed', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel.send(const Pinged(1));
      reader.drain();
      channel.update(); // event 1 fully consumed

      channel.send(const Pinged(2));
      expect(reader.drain().map((e) => e.id), <int>[2]);
    });

    test('a slow reader still receives events after update', () {
      final channel = EventChannel<Pinged>();
      final fast = channel.reader();
      final slow = channel.reader();

      channel.send(const Pinged(1));
      fast.drain(); // slow has not read
      channel.update(); // must keep event 1 for slow

      expect(slow.drain().map((e) => e.id), <int>[1]);
    });

    test('a stalled reader is skipped past the retention window', () {
      final channel = EventChannel<Pinged>(); // retainedUpdates: 2
      final stalled = channel.reader();

      channel.send(const Pinged(1));
      channel.update(); // pass 1: event stays readable (frame N + 1)
      expect(stalled.hasUnread, isTrue);

      channel.update(); // pass 2: retention window exceeded, event expires
      expect(stalled.hasUnread, isFalse);
      expect(stalled.drain(), isEmpty);

      // The channel keeps working normally afterwards.
      channel.send(const Pinged(2));
      expect(stalled.drain().map((e) => e.id), <int>[2]);
    });

    test('a stalled reader cannot grow the buffer without bound', () {
      final channel = EventChannel<Pinged>();
      final active = channel.reader();
      channel.reader(); // stalled: never drains

      for (var frame = 0; frame < 100; frame++) {
        channel.send(Pinged(frame));
        expect(active.drain(), hasLength(1));
        channel.update();
      }
      // Only events inside the retention window can still be buffered.
      channel.send(const Pinged(100));
      expect(active.drain(), hasLength(1));
    });

    test('update reports how many unread events a lagging reader lost', () {
      final channel = EventChannel<Pinged>();
      channel.reader(); // never drains

      channel.send(const Pinged(1));
      channel.send(const Pinged(2));
      expect(channel.update(), 0, reason: 'still within the window');
      expect(channel.update(), 2, reason: 'both events expired unread');
      expect(channel.update(), 0, reason: 'nothing new to lose');
    });

    test('null retainedUpdates keeps events until every reader consumed them',
        () {
      final channel = EventChannel<Pinged>(retainedUpdates: null);
      final slow = channel.reader();

      channel.send(const Pinged(1));
      channel.update();
      channel.update();
      channel.update();

      expect(slow.drain().map((e) => e.id), <int>[1]);
    });

    test('retainedUpdates of 1 expires unread events every pass', () {
      final channel = EventChannel<Pinged>(retainedUpdates: 1);
      final reader = channel.reader();

      channel.send(const Pinged(1));
      channel.update();
      expect(reader.hasUnread, isFalse);
    });

    test('writer sends to readers', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel.writer().send(const Pinged(7));
      expect(reader.drain().map((e) => e.id), <int>[7]);
    });

    test('forEach reads unread events without affecting other readers', () {
      final channel = EventChannel<Pinged>();
      final a = channel.reader();
      final b = channel.reader();

      channel
        ..send(const Pinged(1))
        ..send(const Pinged(2));

      final seen = <int>[];
      a.forEach((event) => seen.add(event.id));

      expect(seen, <int>[1, 2]);
      expect(a.hasUnread, isFalse);
      expect(b.drain().map((e) => e.id), <int>[1, 2]);
    });

    test('forEach leaves cursor unchanged when callback throws', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel
        ..send(const Pinged(1))
        ..send(const Pinged(2));

      expect(
        () => reader.forEach((event) {
          if (event.id == 1) throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(reader.drain().map((e) => e.id), <int>[1, 2]);
    });
  });

  group('World event channels', () {
    test('registers and exposes a channel', () {
      final world = World()..registerEvent<Pinged>();
      final reader = world.eventChannel<Pinged>().reader();
      world.eventChannel<Pinged>().send(const Pinged(3));
      expect(reader.drain().map((e) => e.id), <int>[3]);
    });

    test('throws for an unregistered event type', () {
      final world = World();
      expect(world.eventChannel<Pinged>, throwsStateError);
    });

    test('app reports a lagging reader through onDiagnostic, once per type',
        () {
      final messages = <String>[];
      final app = App(onDiagnostic: messages.add)..addEvent<Pinged>();
      app.start();
      app.world.eventChannel<Pinged>().reader(); // never drains

      app.world.eventChannel<Pinged>().send(const Pinged(1));
      app.updateEvents();
      expect(messages, isEmpty, reason: 'still within the window');

      app.updateEvents();
      expect(messages, hasLength(1));
      expect(messages.single, contains('Pinged'));

      app.world.eventChannel<Pinged>().send(const Pinged(2));
      app.updateEvents();
      app.updateEvents();
      expect(messages, hasLength(1), reason: 'reported once per event type');
    });
  });
}
