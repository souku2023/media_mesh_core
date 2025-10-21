part of '../../media_mesh_core_base.dart';

class Envelope {
  final int v; // protocol version
  final String t; // message type
  final String? n; // name
  final String? id; // correlation id (req/res)
  final int ts; // timestamp ms
  final dynamic d; // data (can be Map/List/primitive)

  const Envelope({
    required this.v,
    required this.t,
    this.n,
    this.id,
    required this.ts,
    this.d,
  });

  Map<String, dynamic> toJson() => {
    'v': v,
    't': t,
    if (n != null) 'n': n,
    if (id != null) 'id': id,
    'ts': ts,
    if (d != null) 'd': d,
  };

  factory Envelope.fromJson(Map<String, dynamic> j) => Envelope(
    v: j['v'] as int,
    t: j['t'] as String,
    n: j['n'] as String?,
    id: j['id'] as String?,
    ts: (j['ts'] as num).toInt(),
    d: j['d'],
  );
}
