import 'db.dart';

/// SMS direction, mirroring Android's Telephony.Sms types.
enum SmsDirection { received, sent, draft, outbox, other }

SmsDirection smsDirectionFromType(int type) {
  switch (type) {
    case 1:
      return SmsDirection.received;
    case 2:
      return SmsDirection.sent;
    case 3:
      return SmsDirection.draft;
    case 4:
      return SmsDirection.outbox;
    default:
      return SmsDirection.other;
  }
}

/// A single SMS from the child's inbox/sent.
class SmsMessage {
  final String address;
  final String body;
  final SmsDirection direction;
  final DateTime? at;

  const SmsMessage({
    required this.address,
    required this.body,
    required this.direction,
    this.at,
  });

  bool get isSent => direction == SmsDirection.sent;
}

/// Reads a child's SMS history from
/// `families/{familyId}/children/{childId}/smsHistory/current`.
class SmsHistoryRepository {
  SmsHistoryRepository._();
  static final instance = SmsHistoryRepository._();

  Stream<List<SmsMessage>> watch(String familyId, String childId,
      {String? deviceId}) {
    return Db.watchReportArray<SmsMessage>(
      deviceId: deviceId,
      familyId: familyId,
      childId: childId,
      collection: 'smsHistory',
      field: 'messages',
      parse: (m) => SmsMessage(
        address: (m['address'] ?? 'Unknown').toString(),
        body: (m['body'] ?? '').toString(),
        direction: smsDirectionFromType((m['type'] as num?)?.toInt() ?? 0),
        at: Db.millis(m['at']),
      ),
    );
  }
}
