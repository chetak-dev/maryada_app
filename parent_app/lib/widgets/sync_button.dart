import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/family_repository.dart';
import 'access_scope.dart';
import 'feedback.dart';

/// Asks every device in the family to report now.
///
/// Firestore already streams whatever the devices have sent, so this is not a
/// refresh of the parent's screen — it nudges the devices themselves, which
/// otherwise report on their own throttle.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key, required this.uid});

  final String? uid;

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _busy = false;
  String _familyId = '';
  StreamSubscription<String>? _familySub;

  @override
  void initState() {
    super.initState();
    final uid = widget.uid;
    if (uid != null && Db.ready) {
      _familySub = FamilyRepository.instance
          .watchMyFamilyId(uid)
          .listen((id) {
        if (mounted) setState(() => _familyId = id);
      });
    }
  }

  @override
  void dispose() {
    _familySub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_busy || _familyId.isEmpty || !Db.ready) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    _spin.repeat();
    try {
      final count = await FamilyRepository.instance.requestSync(_familyId);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'No profiles to sync yet.'
                : 'Asked $count profile${count == 1 ? '' : 's'} to report. '
                      'Devices that are switched off will report when they '
                      'come back.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\u2019t sync \u2014 ${friendlyError(e)}')),
      );
    } finally {
      _spin.stop();
      _spin.reset();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A view-only parent cannot write to the profiles, so the button would
    // always fail for them.
    if (!AccessScope.of(context) || _familyId.isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Sync all devices',
      onPressed: _busy ? null : _sync,
      icon: RotationTransition(
        turns: _spin,
        child: const Icon(Icons.sync_rounded),
      ),
    );
  }
}
