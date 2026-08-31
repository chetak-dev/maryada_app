import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// A child to clear, with its family.
class ChildRef {
  final String familyId;
  final String childId;
  final String name;
  final String ownerEmail;
  const ChildRef({
    required this.familyId,
    required this.childId,
    required this.name,
    required this.ownerEmail,
  });
}

/// Site-admin data maintenance: deletes a child's **activity/history** while
/// leaving structural data (accounts, families, children, pairing, rules)
/// intact so devices stay paired and monitoring continues.
///
/// Cleared per child: web / call / SMS / YouTube history, usage summary,
/// location trail, chat threads & messages; plus family alerts for that child.
class DataClearRepository {
  DataClearRepository._();
  static final instance = DataClearRepository._();

  /// Single "current" docs that hold arrays of timestamped items (`at` millis).
  static const _arrayDocs = <String, List<String>>{
    'webHistory': ['visited', 'blocked', 'searches'],
    'callHistory': ['calls'],
    'smsHistory': ['messages'],
    'youtubeHistory': ['videos'],
    'appCalls': ['calls'],
  };

  /// Lists every paired child across all families (site admin only).
  Future<List<ChildRef>> listAllChildren() async {
    final out = <ChildRef>[];
    final families = await Db.families.get();
    // Map ownerUid -> email for a friendlier label.
    final users = await Db.instance.collection('users').get();
    final emailByUid = {
      for (final u in users.docs) u.id: (u.data()['email'] ?? '').toString(),
    };
    for (final fam in families.docs) {
      final ownerUid = (fam.data()['ownerUid'] ?? '').toString();
      final ownerEmail = emailByUid[ownerUid] ?? '';
      final kids = await fam.reference.collection('children').get();
      for (final k in kids.docs) {
        if (k.data()['paired'] != true) continue;
        out.add(ChildRef(
          familyId: fam.id,
          childId: k.id,
          name: (k.data()['name'] ?? 'Child').toString(),
          ownerEmail: ownerEmail,
        ));
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Clears activity for [children]. When [cutoff] is null, removes ALL history;
  /// otherwise removes only records older than [cutoff]. Children and their
  /// collections are cleared in parallel — sequential awaits made a full wipe
  /// feel stuck for minutes on large histories.
  Future<void> clearActivity({
    required List<ChildRef> children,
    DateTime? cutoff,
  }) async {
    final cutoffMs = cutoff?.millisecondsSinceEpoch;
    // Group included child ids per family for alert filtering.
    final childIdsByFamily = <String, Set<String>>{};
    for (final c in children) {
      childIdsByFamily.putIfAbsent(c.familyId, () => {}).add(c.childId);
    }
    await Future.wait([
      for (final c in children) _clearChild(c.familyId, c.childId, cutoffMs),
    ]);
    // Alerts are activity too: the site admin's clear removes the family's
    // whole feed, not only rows tagged with the included children — alerts of
    // deleted or unpaired profiles used to survive every wipe.
    await Future.wait([
      for (final familyId in childIdsByFamily.keys)
        _clearAlerts(familyId, null, cutoffMs),
    ]);
  }

  /// Deletes a profile and every known document below it. Firestore does not
  /// cascade-delete subcollections when their parent document is removed.
  ///
  /// Refused while any device is still linked — removing the devices first is
  /// what unpairs them cleanly; deleting the profile out from under a live
  /// installation would leave it enforcing rules nobody can see or change.
  Future<void> deleteProfile(String familyId, String childId) async {
    final childRef = Db.child(familyId, childId);
    final child = await childRef.get();
    final raw = child.data()?['devices'];
    final devices = raw is Map
        ? {
            for (final e in raw.entries)
              e.key.toString(): (e.value is Map)
                  ? Map<String, dynamic>.from(e.value as Map)
                  : const <String, dynamic>{},
          }
        : const <String, Map<String, dynamic>>{};
    final active = devices.values.where((d) => d['revoked'] != true).length;
    // A device paired by a build that predates the `devices` map writes only
    // the subcollection, so the map can be empty while an installation is very
    // much alive. `deviceUid` is stamped by every build, and deleting the
    // profile out from under it would leave it enforcing rules nobody can see.
    final boundUid = (child.data()?['deviceUid'] ?? '').toString();
    final legacyLive = active == 0 &&
        boundUid.isNotEmpty &&
        child.data()?['paired'] == true;
    if (active > 0 || legacyLive) {
      final count = active > 0 ? active : 1;
      throw StateError(
          'This profile still has $count linked device(s). Remove them first.');
    }

    // Delete the profile first so connected installations immediately unpair.
    await childRef.delete();
    await _clearChild(familyId, childId, null);
    // Devices live in the profile's `devices` map now; this sweeps the old
    // subcollection, which Firestore does not cascade-delete, off profiles
    // created before that change.
    await _deleteQuery(childRef.collection('devices'));
    await _clearAlerts(familyId, {childId}, null);

    // Pairing-code listing is deliberately forbidden by the security rules.
    // Existing one-time codes expire after 15 minutes, so profile deletion must
    // not fail after the profile is already gone just to clean one early.
    try {
      final codes =
        await Db.pairingCodes.where('childId', isEqualTo: childId).get();
      await _deleteRefs(codes.docs
        .where((d) => d.data()['familyId'] == familyId)
        .map((d) => d.reference)
        .toList());
    } catch (_) {}

    // A connected child removes this itself; this also cleans up devices that
    // may never come online again. Older deployed rules may reject it, so the
    // profile deletion must not depend on this best-effort cleanup.
    for (final deviceId in devices.keys) {
      try {
        await Db.instance.collection('devices').doc(deviceId).delete();
      } catch (_) {}
    }
  }

  /// Full activity wipe for one child — history, usage, location, chats and
  /// their alerts. Used when a profile's last device is removed, so nothing a
  /// removed device reported lingers anywhere.
  Future<void> clearChildActivity(String familyId, String childId) async {
    await _clearChild(familyId, childId, null);
    await _clearAlerts(familyId, {childId}, null);
    // Every device's installed-apps report, so the app-rules list empties too.
    try {
      final reports = await Db.child(familyId, childId)
          .collection('reports')
          .get();
      await Future.wait([
        for (final doc in reports.docs)
          if (doc.id.startsWith('installedApps')) doc.reference.delete(),
      ]);
    } catch (_) {}
  }

  Future<void> _clearChild(
      String familyId, String childId, int? cutoffMs) async {
    final childRef =
        Db.families.doc(familyId).collection('children').doc(childId);

    Future<void> clearArrayDoc(MapEntry<String, List<String>> entry) async {
      // One document per device (plus a legacy shared `current`).
      final docs = await childRef.collection(entry.key).get();
      await Future.wait([
        for (final doc in docs.docs)
          () async {
            if (cutoffMs == null) {
              await doc.reference.delete();
              return;
            }
            final data = doc.data();
            final update = <String, dynamic>{};
            var changed = false;
            for (final key in entry.value) {
              final list = (data[key] as List?) ?? const [];
              final kept = list
                  .where((m) =>
                      m is Map && ((m['at'] as num?)?.toInt() ?? 0) >= cutoffMs)
                  .toList();
              if (kept.length != list.length) {
                update[key] = kept;
                changed = true;
              }
            }
            if (changed) {
              await doc.reference.set(update, SetOptions(merge: true));
            }
          }(),
      ]);
    }

    Future<void> clearChats() async {
      final threads = await childRef.collection('chatThreads').get();
      await Future.wait([
        for (final t in threads.docs)
          () async {
            final msgs = t.reference.collection('messages');
            if (cutoffMs == null) {
              await _deleteQuery(msgs);
              await t.reference.delete();
            } else {
              await _deleteQuery(msgs.where('at', isLessThan: cutoffMs));
              final remaining = await msgs.limit(1).get();
              if (remaining.docs.isEmpty) await t.reference.delete();
            }
          }(),
      ]);
    }

    final loc = childRef.collection('locationHistory');
    await Future.wait([
      for (final entry in _arrayDocs.entries) clearArrayDoc(entry),
      // Usage is a document per device now, plus the legacy shared `summary`.
      if (cutoffMs == null) _deleteQuery(childRef.collection('usage')),
      _deleteQuery(cutoffMs == null
          ? loc
          : loc.where('at',
              isLessThan: Timestamp.fromMillisecondsSinceEpoch(cutoffMs))),
      clearChats(),
    ]);

    // Tell the device (it watches its own child doc). Without this the
    // child's local buffers re-upload the wiped web/YouTube history on the
    // next flush, and its chat dedup set suppresses re-capturing messages
    // still on screen — which read as "WhatsApp stopped working" to an admin.
    // Skipped during profile deletion: a merge write would resurrect the
    // just-deleted child doc as a stub.
    final childDoc = await childRef.get();
    if (childDoc.exists) {
      await childRef.set(
          {'historyClearedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    }
  }

  /// Deletes the family's alerts. With [includedChildIds] null every alert
  /// goes; otherwise only those children's (plus unattributed ones).
  Future<void> _clearAlerts(
      String familyId, Set<String>? includedChildIds, int? cutoffMs) async {
    Query<Map<String, dynamic>> q =
        Db.families.doc(familyId).collection('alerts');
    if (cutoffMs != null) {
      q = q.where('at',
          isLessThan: Timestamp.fromMillisecondsSinceEpoch(cutoffMs));
    }
    final snap = await q.get();
    final refs = snap.docs
        .where((d) {
          if (includedChildIds == null) return true;
          final cid = (d.data()['childId'] ?? '').toString();
          // Delete alerts for included children (and unattributed ones).
          return cid.isEmpty || includedChildIds.contains(cid);
        })
        .map((d) => d.reference)
        .toList();
    await _deleteRefs(refs);
  }

  /// Pages through a query and batch-deletes every matching doc.
  Future<void> _deleteQuery(Query<Map<String, dynamic>> q) async {
    while (true) {
      final snap = await q.limit(450).get();
      if (snap.docs.isEmpty) break;
      final batch = Db.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 450) break;
    }
  }

  Future<void> _deleteRefs(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 300) {
      final batch = Db.instance.batch();
      for (final r in refs.skip(i).take(300)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }
}
