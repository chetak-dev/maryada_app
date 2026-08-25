import 'db.dart';

/// A voice or video call placed inside an app (WhatsApp today).
///
/// These never reach the phone's call log — the app keeps them in its own
/// store — so they are captured separately from [CallRecord] and shown with
/// the chats they belong to.
class AppCall {
  final String app;
  final String contact;
  final bool video;
  final bool incoming;
  final bool missed;
  final DateTime? at;
  final Duration duration;

  const AppCall({
    required this.app,
    required this.contact,
    this.video = false,
    this.incoming = false,
    this.missed = false,
    this.at,
    this.duration = Duration.zero,
  });
}

/// Reads in-app calls from
/// `families/{familyId}/children/{childId}/appCalls/{deviceUid}`.
class AppCallsRepository {
  AppCallsRepository._();
  static final instance = AppCallsRepository._();

  Stream<List<AppCall>> watch(
    String familyId,
    String childId, {
    String? deviceId,
    String? platform,
  }) {
    return Db.watchReportArray<AppCall>(
      deviceId: deviceId,
      includeLegacyCurrent: platform != 'windows',
      familyId: familyId,
      childId: childId,
      collection: 'appCalls',
      field: 'calls',
      parse: (m) {
        final contact = (m['contact'] ?? '').toString().trim();
        if (contact.isEmpty) return null;
        return AppCall(
          app: (m['app'] ?? 'WhatsApp').toString(),
          contact: contact,
          video: m['video'] == true,
          incoming: m['incoming'] == true,
          missed: m['missed'] == true,
          at: Db.millis(m['at']),
          duration: Duration(seconds: (m['seconds'] as num?)?.toInt() ?? 0),
        );
      },
    ).map((calls) {
      final list = [...calls]..sort(
          (a, b) => (b.at?.millisecondsSinceEpoch ?? 0).compareTo(
            a.at?.millisecondsSinceEpoch ?? 0,
          ),
        );
      return _merge(list);
    });
  }

  /// Collapses the notification updates of a single call into one row.
  ///
  /// The child device already groups them, but a call recorded by a build that
  /// did not, or seen by two devices at once, still arrives as several rows —
  /// and a parent seeing "Incoming" twice for one call has no way to tell it
  /// was the same call.
  static const _sessionGap = Duration(minutes: 2);

  List<AppCall> _merge(List<AppCall> sorted) {
    final out = <AppCall>[];
    for (final call in sorted) {
      final at = call.at;
      final previous = out.isEmpty ? null : out.last;
      final sameCall =
          previous != null &&
          previous.app == call.app &&
          previous.contact.toLowerCase() == call.contact.toLowerCase() &&
          at != null &&
          previous.at != null &&
          previous.at!.difference(at).abs() <= _sessionGap;
      if (!sameCall) {
        out.add(call);
        continue;
      }
      // The list is newest first, so `previous` is the later sighting; keep the
      // earliest start and whichever update actually learned something.
      out[out.length - 1] = AppCall(
        app: previous.app,
        contact: previous.contact,
        video: previous.video || call.video,
        incoming: previous.incoming || call.incoming,
        // Any evidence it connected beats a "missed" from the ringing notice.
        missed: previous.missed &&
            call.missed &&
            previous.duration.inSeconds == 0 &&
            call.duration.inSeconds == 0,
        at: at,
        duration: previous.duration >= call.duration
            ? previous.duration
            : call.duration,
      );
    }
    return out;
  }
}
