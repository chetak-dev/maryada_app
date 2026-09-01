import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tag.dart';
import 'db.dart';

/// Tags for grouping a family's profiles: `families/{familyId}/tags/{tagId}`.
///
/// The site admin owns the vocabulary (the rules refuse a write from anyone
/// else); a guardian with edit access assigns them by writing `tagIds` on the
/// child document, which is read with the profile itself and so costs nothing.
class TagsRepository {
  TagsRepository._();
  static final instance = TagsRepository._();

  CollectionReference<Map<String, dynamic>> _col(String familyId) =>
      Db.families.doc(familyId).collection('tags');

  Stream<List<FamilyTag>> watch(String familyId) {
    if (familyId.isEmpty) return Stream.value(const <FamilyTag>[]);
    return _col(familyId).snapshots().map(
      (s) =>
          s.docs.map((d) => FamilyTag.fromMap(d.id, d.data())).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ),
    );
  }

  Future<List<FamilyTag>> load(String familyId) async {
    if (familyId.isEmpty) return const [];
    final snap = await _col(familyId).get();
    return snap.docs.map((d) => FamilyTag.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Site admin only. Names are unique per family so a filter chip always means
  /// one thing.
  Future<void> create(String familyId, String name, int color) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('a tag needs a name.');
    await _requireUnusedName(familyId, trimmed, null);
    await _col(familyId).add({
      'name': trimmed,
      'color': color,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rename(String familyId, String tagId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('a tag needs a name.');
    await _requireUnusedName(familyId, trimmed, tagId);
    await _col(
      familyId,
    ).doc(tagId).set({'name': trimmed}, SetOptions(merge: true));
  }

  Future<void> _requireUnusedName(
    String familyId,
    String name,
    String? exceptId,
  ) async {
    final existing = await load(familyId);
    final clash = existing.any(
      (t) => t.id != exceptId && t.name.toLowerCase() == name.toLowerCase(),
    );
    if (clash) throw StateError('there is already a tag called "$name".');
  }

  /// How many of the family's profiles currently wear this tag.
  Future<int> usageCount(String familyId, String tagId) async {
    final kids = await Db.children(
      familyId,
    ).where('tagIds', arrayContains: tagId).count().get();
    return kids.count ?? 0;
  }

  /// Removes the tag and strips it from every profile wearing it — a profile
  /// left holding a deleted tag id would filter into a group that no longer
  /// exists.
  Future<void> delete(String familyId, String tagId) async {
    final wearing = await Db.children(
      familyId,
    ).where('tagIds', arrayContains: tagId).get();
    for (final doc in wearing.docs) {
      await doc.reference.set({
        'tagIds': FieldValue.arrayRemove([tagId]),
      }, SetOptions(merge: true));
    }
    await _col(familyId).doc(tagId).delete();
  }

  /// Guardian action: which tag this profile wears.
  ///
  /// A profile belongs to at most one tag. The field stays an array so the
  /// `arrayContains` queries above keep working, and so profiles tagged before
  /// that rule still parse.
  Future<void> setChildTags(
    String familyId,
    String childId,
    List<String> tagIds,
  ) {
    if (tagIds.length > 1) {
      throw StateError('a profile can only belong to one tag.');
    }
    return Db.children(
      familyId,
    ).doc(childId).set({'tagIds': tagIds}, SetOptions(merge: true));
  }
}
