import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand_mark.dart';

/// Add-child flow: name the child, generate a pairing code, and show the
/// device setup steps. Uses the real repository when [familyId] is set and
/// Firebase is connected; otherwise generates a local demo code.
class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key, this.familyId});

  final String? familyId;

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _name = TextEditingController();
  String? _code;
  bool _busy = false;
  String? _childId;
  bool _linked = false;
  StreamSubscription<Object?>? _linkSub;

  @override
  void dispose() {
    _linkSub?.cancel();
    _cleanupIfUnlinked();
    _name.dispose();
    super.dispose();
  }

  /// If the parent leaves before the child links, remove the placeholder child
  /// doc so it never appears in the family list (only linked children show).
  void _cleanupIfUnlinked() {
    final fid = widget.familyId;
    final cid = _childId;
    if (fid == null || cid == null || _linked) return;
    final ref = Db.families.doc(fid).collection('children').doc(cid);
    ref.get().then((doc) {
      if (doc.exists && doc.data()?['paired'] != true) {
        ref.delete();
      }
    }).catchError((_) {});
  }

  /// Watches the new child's doc; when the device links (paired == true) the
  /// screen closes automatically so the dashboard shows it as protected.
  void _watchForLink(String childId) {
    final fid = widget.familyId;
    if (fid == null) return;
    _linkSub?.cancel();
    _linkSub = Db.families
        .doc(fid)
        .collection('children')
        .doc(childId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data != null && data['paired'] == true) {
        _linked = true;
        _linkSub?.cancel();
        if (!mounted) return;
        final name = _name.text.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${name.isEmpty ? 'Device' : name} is linked and protected.')),
        );
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _generate() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the child’s name first.')),
      );
      return;
    }
    final live = widget.familyId != null && Db.ready;
    if (live) {
      setState(() => _busy = true);
      try {
        final repo = FamilyRepository.instance;
        final child = await repo.addChild(
            familyId: widget.familyId!, name: _name.text.trim());
        final code = await repo.generatePairingCode(
            familyId: widget.familyId!, childId: child.id);
        if (!mounted) return;
        setState(() {
          _code = code;
          _busy = false;
        });
        _childId = child.id;
        _watchForLink(child.id);
      } catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t create pairing code: $e')),
        );
      }
      return;
    }
    // Demo mode: local one-time code.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    setState(() {
      _code =
          List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add a child')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          Center(child: const BrandMark(size: 64)),
          const SizedBox(height: AppSpacing.md),
          Text(
            _code == null ? 'Name this child' : 'Pair the device',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _code == null
                ? 'We’ll create a one-time code to link their device.'
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
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Child’s name',
                        hintText: 'e.g. Aarav',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
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
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
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
                  child: Container(width: 2, color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
