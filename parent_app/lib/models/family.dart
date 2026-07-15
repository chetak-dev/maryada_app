/// A family: the top-level container linking guardian accounts (parentUids) to
/// their children. Firestore: `families/{familyId}`.
class FamilyModel {
  final String id;
  final String name;
  final String ownerUid;
  final List<String> parentUids;

  const FamilyModel({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.parentUids,
  });

  factory FamilyModel.fromMap(String id, Map<String, dynamic> map) {
    return FamilyModel(
      id: id,
      name: (map['name'] ?? 'My Family').toString(),
      ownerUid: (map['ownerUid'] ?? '').toString(),
      parentUids: (map['parentUids'] is List)
          ? List<String>.from((map['parentUids'] as List).map((e) => '$e'))
          : const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerUid': ownerUid,
        'parentUids': parentUids,
      };
}
