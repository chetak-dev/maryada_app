import 'db.dart';

/// The direction/outcome of a call, mirroring Android's CallLog types.
enum CallKind { incoming, outgoing, missed, rejected, blocked, voicemail, unknown }

extension CallKindInfo on CallKind {
  static CallKind fromAndroidType(int type) {
    switch (type) {
      case 1:
        return CallKind.incoming;
      case 2:
        return CallKind.outgoing;
      case 3:
        return CallKind.missed;
      case 4:
        return CallKind.voicemail;
      case 5:
        return CallKind.rejected;
      case 6:
        return CallKind.blocked;
      default:
        return CallKind.unknown;
    }
  }

  String get label {
    switch (this) {
      case CallKind.incoming:
        return 'Incoming';
      case CallKind.outgoing:
        return 'Outgoing';
      case CallKind.missed:
        return 'Missed';
      case CallKind.rejected:
        return 'Rejected';
      case CallKind.blocked:
        return 'Blocked';
      case CallKind.voicemail:
        return 'Voicemail';
      case CallKind.unknown:
        return 'Call';
    }
  }
}

/// A single call from the child's call log.
class CallRecord {
  final String number;
  final String? name;
  final CallKind kind;
  final DateTime? at;
  final Duration duration;

  const CallRecord({
    required this.number,
    this.name,
    required this.kind,
    this.at,
    this.duration = Duration.zero,
  });

  String get display => (name != null && name!.isNotEmpty) ? name! : number;
}

/// Reads a child's call history from
/// `families/{familyId}/children/{childId}/callHistory/current`.
class CallHistoryRepository {
  CallHistoryRepository._();
  static final instance = CallHistoryRepository._();

  Stream<List<CallRecord>> watch(String familyId, String childId,
      {String? deviceId}) {
    return Db.watchReportArray<CallRecord>(
      deviceId: deviceId,
      familyId: familyId,
      childId: childId,
      collection: 'callHistory',
      field: 'calls',
      parse: (m) => CallRecord(
        number: (m['number'] ?? 'Unknown').toString(),
        name: (m['name'] ?? '').toString(),
        kind: CallKindInfo.fromAndroidType((m['type'] as num?)?.toInt() ?? 0),
        at: Db.millis(m['at']),
        duration: Duration(seconds: (m['duration'] as num?)?.toInt() ?? 0),
      ),
    );
  }
}
