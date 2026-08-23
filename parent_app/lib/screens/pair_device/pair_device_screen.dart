import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../data/user_repository.dart';
import '../../models/child.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
import '../../widgets/feedback.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/net_guard.dart';
import '../../widgets/read_only_banner.dart';

/// Pairs a new device to an existing profile: name the device, generate a
/// one-time code, enter it on the device. Reached from the profile's Devices
/// section — the profile is already chosen.
class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({
    super.key,
    required this.familyId,
    required this.child,
  });

  final String familyId;
  final Child child;

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  final _deviceName = TextEditingController();
  String? _code;
  bool _busy = false;
  String? _nameError;
  StreamSubscription<Object?>? _linkSub;
  Set<String> _devicesBefore = const {};

  @override
  void dispose() {
    _linkSub?.cancel();
    _deviceName.dispose();
    super.dispose();
  }

  /// Watches the profile's device list; a new active installation appearing
  /// means the code was redeemed — even when the profile already had devices.
  void _watchForLink() {
    _linkSub?.cancel();
    _linkSub = Db.children(widget.familyId)
        .doc(widget.child.id)
        .collection('devices')
        .snapshots()
        .listen((snap) {
      final active = snap.docs
          .where((d) => d.data()['revoked'] != true)
          .map((d) => d.id)
          .toSet();
      if (active.difference(_devicesBefore).isEmpty) return;
      _linkSub?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${widget.child.name}’s device is linked and protected.')),
      );
      Navigator.of(context).pop();
    });
  }

  /// The admin's limit counts paired devices across the family — profiles are
  /// free, devices are what's scarce. True (and explains itself) at the cap.
  Future<bool> _deviceLimitReached() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final me = await UserRepository.instance.watch(uid).first;
      final max = me?.maxChildren ?? 0;
      if (max <= 0) return false;
      final devices = await Db.instance
          .collection('devices')
          .where('familyId', isEqualTo: widget.familyId)
          .count()
          .get();
      if ((devices.count ?? 0) < max) return false;
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(
                'Device limit reached ($max). Ask your admin to raise it.'),
          ));
      }
      return true;
    } catch (_) {
      // Counting is best-effort; pairing itself stays guarded by the rules.
      return false;
    }
  }

  Future<void> _generate() async {
    // Pairing a device is a change, so view-only access can't do it — the
    // entry point is hidden for them, but this screen must refuse on its own.
    if (!AccessScope.of(context)) return;
    final deviceName = _deviceName.text.trim();
    if (deviceName.isEmpty) {
      setState(() => _nameError = 'Give the device a name first.');
      return;
    }
    setState(() => _nameError = null);
    if (!await Net.require(context)) return;
    if (!mounted) return;
    if (await _deviceLimitReached()) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      // Snapshot the active devices first, so the link detector only fires on
      // an installation that appears after this code was issued.
      final before = await Db.children(widget.familyId)
          .doc(widget.child.id)
          .collection('devices')
          .get();
      _devicesBefore = before.docs
          .where((d) => d.data()['revoked'] != true)
          .map((d) => d.id)
          .toSet();
      final code = await FamilyRepository.instance.generatePairingCode(
          familyId: widget.familyId,
          childId: widget.child.id,
          deviceName: deviceName);
      if (!mounted) return;
      setState(() {
        _code = code;
        _busy = false;
      });
      _watchForLink();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Couldn’t create a pairing code — ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.child.name;
    final canEdit = AccessScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Add a device · $name')),
      body: !canEdit
          ? const ReadOnlyBanner()
          : ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          Center(child: const BrandMark(size: 64)),
          const SizedBox(height: AppSpacing.md),
          Text(
            _code == null ? 'Name the device' : 'Pair the device',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _code == null
                ? 'A profile can hold several devices — a phone, a tablet, '
                    'a laptop. Name this one so you can tell them apart.'
                : 'Enter this code on the child’s device during setup.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_code == null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _deviceName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Device name',
                        hintText: 'e.g. $name’s phone / tablet / laptop',
                        prefixIcon: const Icon(Icons.devices_other_rounded),
                        errorText: _nameError,
                      ),
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                      onSubmitted: (_) => _busy ? null : _generate(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _busy ? null : _generate,
                      icon: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Generate pairing code'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            _CodeCard(code: _code!),
            const SizedBox(height: AppSpacing.lg),
            Text('Setup steps', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            const _Step(
              n: 1,
              title: 'Install Maryada',
              body: 'Put the Maryada app on the child’s Android device.',
            ),
            const _Step(
              n: 2,
              title: 'Enroll as a managed device',
              body:
                  'Follow the on-screen setup so the app can’t be removed without you.',
            ),
            const _Step(
              n: 3,
              title: 'Enter the code',
              body: 'Type the code above to link the device to your family.',
              last: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.sm),
                Text('Waiting for the device to link\u2026',
                    style: TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Text(
            'PAIRING CODE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy code'),
          ),
          Text(
            'Expires in 15 minutes',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.body,
    this.last = false,
  });

  final int n;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child:
                      Container(width: 2, color: AppColors.borderOf(context)),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: TextStyle(
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
