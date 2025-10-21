part of '../../media_mesh_core_base.dart';

typedef AnyEventHandler = void Function(String event, dynamic payload);

class Connection {
  final String host;
  final int port;

  // Map of event name -> broadcast stream for observers
  final Map<String, StreamController<dynamic>> _channels =
      <String, StreamController<dynamic>>{};

  // Broadcast stream for "any" listeners (receives {event, payload})
  final StreamController<Map<String, dynamic>> _any =
      StreamController<Map<String, dynamic>>.broadcast();

  // Function that actually writes bytes/strings to the transport.
  // Set this via [attachSender].
  void Function(String raw)? _sender;

  Connection({required this.host, required this.port});

  /// Subscribe to a specific event.
  /// Returns a subscription you can `.cancel()` to stop listening.
  StreamSubscription<dynamic> onEvent(
    String event,
    void Function(dynamic payload) handler,
  ) {
    final StreamController<dynamic> controller = _channels.putIfAbsent(
      event,
      () => StreamController<dynamic>.broadcast(),
    );
    return controller.stream.listen(handler);
  }

  /// Subscribe to *all* events.
  StreamSubscription<dynamic> onAny(AnyEventHandler handler) {
    return _any.stream.listen(
      (Map<String, dynamic> m) => handler(m['event'] as String, m['payload']),
    );
  }

  /// INTERNAL: Call this when your transport receives an event packet.
  /// This dispatches to all observers of [event] and any onAny() listeners.
  void deliver(String event, dynamic payload) {
    final StreamController<dynamic>? c = _channels[event];
    if (c != null && !c.isClosed) {
      c.add(payload);
    }
    if (!_any.isClosed) {
      _any.add(<String, dynamic>{'event': event, 'payload': payload});
    }
  }

  /// Attach a function that writes raw strings to your underlying transport.
  /// For example: `socket.add(jsonString)` or `webSocket.sink.add(jsonString)`.
  void attachSender(void Function(String raw) sender) {
    _sender = sender;
  }

  /// Send an event to the other side. Encodes as JSON: {"event": "...", "payload": ...}
  void send(String event, dynamic payload) {
    final dynamic s = _sender;
    if (s == null) {
      throw StateError('No sender attached. Call attachSender(...) first.');
    }
    s(jsonEncode(<String, dynamic>{'event': event, 'payload': payload}));
  }

  /// Optional convenience: one-shot listen.
  Future<dynamic> once(String event) async {
    final StreamController<dynamic> controller = _channels.putIfAbsent(
      event,
      () => StreamController<dynamic>.broadcast(),
    );
    return controller.stream.first;
  }

  /// Clean up.
  Future<void> dispose() async {
    for (final StreamController<dynamic> c in _channels.values) {
      await c.close();
    }
    await _any.close();
  }
}
