part of '../../media_mesh_core_base.dart';

typedef Json = Map<String, dynamic>;

String _uuid() {
  // Tiny unique-ish ID for demo purposes
  final Random r = Random();
  final List<int> bytes = List<int>.generate(12, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

class WsClient {
  static const int heartBeatIntervalConstant = 15;
  static const int requestTimeoutConstant = 10;
  static const int maxBackoffConstant = 20;
  final Uri uri;
  final Duration heartbeatInterval;
  final Duration requestTimeout;
  final Duration maxBackoff;
  final int protocolVersion;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final Map<String, StreamController<Envelope>> _eventControllers =
      <String, StreamController<Envelope>>{};
  final Map<String, Completer<Envelope>> _pending =
      <String, Completer<Envelope>>{};
  Timer? _hbTimer;
  bool _manuallyClosed = false;
  int _retries = 0;

  WsClient(
    this.uri, {
    this.heartbeatInterval = const Duration(seconds: heartBeatIntervalConstant),
    this.requestTimeout = const Duration(seconds: requestTimeoutConstant),
    this.maxBackoff = const Duration(seconds: maxBackoffConstant),
    this.protocolVersion = 1,
  });

  bool get isConnected => _channel != null;

  // Public API ---------------------------------------------------------------

  Future<void> connect() async {
    _manuallyClosed = false;
    await _open();
  }

  Future<void> close([int code = 1000, String reason = 'normal']) async {
    _manuallyClosed = true;
    _hbTimer?.cancel();
    _hbTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close(code, reason);
    _channel = null;
  }

  /// Send a fire-and-forget event.
  void sendEvent(String name, dynamic data) {
    _send(
      Envelope(
        v: protocolVersion,
        t: 'event',
        n: name,
        ts: DateTime.now().millisecondsSinceEpoch,
        d: data,
      ),
    );
  }

  /// Send a request and await a response.
  Future<Envelope> request(String name, dynamic data) {
    final String id = _uuid();
    final Envelope env = Envelope(
      v: protocolVersion,
      t: 'req',
      n: name,
      id: id,
      ts: DateTime.now().millisecondsSinceEpoch,
      d: data,
    );
    final Completer<Envelope> c = Completer<Envelope>();
    _pending[id] = c;
    _send(env);

    // timeout
    Timer(requestTimeout, () {
      if (!c.isCompleted) {
        _pending.remove(id);
        c.completeError(TimeoutException('Request $name timed out'));
      }
    });
    return c.future;
  }

  /// Stream of envelopes for a specific event name.
  Stream<Envelope> onEvent(String name) => _eventControllers
      .putIfAbsent(name, () => StreamController.broadcast())
      .stream;

  // Internals ---------------------------------------------------------------

  Future<void> _open() async {
    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: _onError,
        cancelOnError: true,
      );
      _startHeartbeat();
      _retries = 0;
    } catch (e) {
      await _retryDelay();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final Json map = jsonDecode(raw as String) as Json;
      final Envelope env = Envelope.fromJson(map);

      switch (env.t) {
        case 'pong':
          // ok
          break;
        case 'ping':
          // answer
          _send(
            Envelope(
              v: protocolVersion,
              t: 'pong',
              ts: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          break;
        case 'res':
          final String? id = env.id;
          if (id != null && _pending.containsKey(id)) {
            _pending.remove(id)!.complete(env);
          }
          break;
        case 'event':
        case 'sys':
        case 'req':
          if (env.n != null) {
            final StreamController<Envelope>? ctrl = _eventControllers[env.n!];
            ctrl?.add(env);
          }
          // If it's 'req', app code could respond by listening on that event
          // and sending 'res'.
          break;
        default:
          // ignore unknown t
          break;
      }
    } catch (_) {
      // ignore malformed
    }
  }

  void _onDone() {
    _cleanupSocket();
    if (!_manuallyClosed) {
      _retryDelay();
    }
  }

  void _onError(Object error, StackTrace st) {
    _cleanupSocket();
    if (!_manuallyClosed) {
      _retryDelay();
    }
  }

  void _cleanupSocket() {
    _hbTimer?.cancel();
    _hbTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel = null;
  }

  Future<void> _retryDelay() async {
    _retries++;
    final Duration delay = Duration(
      milliseconds: min(
        maxBackoff.inMilliseconds,
        500 * pow(2, _retries).toInt() + Random().nextInt(500),
      ),
    );
    await Future<dynamic>.delayed(delay);
    if (!_manuallyClosed) {
      await _open();
    }
  }

  void _startHeartbeat() {
    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(heartbeatInterval, (_) {
      _send(
        Envelope(
          v: protocolVersion,
          t: 'ping',
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  void _send(Envelope env) {
    final WebSocketChannel? ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(env.toJson()));
  }
}
