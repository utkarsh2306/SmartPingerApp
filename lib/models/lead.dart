// models/lead.dart
class Lead {
  final int? id;
  final String phone;
  final String? name;
  final String type; // incoming, outgoing, missed
  final int timestamp;
  final bool blocked;
  final int? lastContacted;
  final int count;
  final String source;

  Lead({
    this.id,
    required this.phone,
    this.name,
    required this.type,
    required this.timestamp,
    this.blocked = false,
    this.lastContacted,
    this.count = 1,
    this.source = 'call_log',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phone': phone,
      'name': name,
      'type': type,
      'timestamp': timestamp,
      'blocked': blocked ? 1 : 0,
      'last_contacted': lastContacted,
      'count': count,
      'source': source,
    };
  }

  factory Lead.fromMap(Map<String, dynamic> map) {
    return Lead(
      id: map['id'] as int?,
      phone: map['phone'] as String? ?? '',
      name: map['name'] as String?,
      type: map['type'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      blocked: (map['blocked'] as int? ?? 0) == 1,
      lastContacted: map['last_contacted'] as int?,
      count: map['count'] as int? ?? 1,
      source: map['source'] as String? ?? 'call_log',
    );
  }
}
