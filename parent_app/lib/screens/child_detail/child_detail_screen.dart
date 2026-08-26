import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_update_repository.dart';
import '../../data/db.dart';
import '../../data/device_repository.dart';
import '../../data/family_repository.dart';
import '../../models/child.dart';
import '../../models/device.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
import '../../widgets/child_devices.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/feedback.dart';
import '../../widgets/net_guard.dart';
import '../../widgets/typed_danger_dialog.dart';
import '../../widgets/whatsapp_mark.dart';
import '../activity/activity_screen.dart';
import '../app_rules/app_rules_screen.dart';
import '../call_history/call_history_screen.dart';
import '../chat_history/chat_history_screen.dart';
import '../location/location_screen.dart';
import '../pair_device/pair_device_screen.dart';
import '../sms_history/sms_history_screen.dart';
import '../youtube_history/youtube_history_screen.dart';

/// Per-child control center: the profile's devices, and the activity and rule
/// areas that open scoped to the selected device.
class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({super.key, required this.child, this.familyId});

  final Child child;
  final String? familyId;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  // The child on screen, which the switcher can change without a round trip
  // back to the list.
  late Child _child = widget.child;
  late String? _familyId = widget.familyId;
  late String _name = widget.child.name;

  /// The newest published child build, so a device still on an older one can
  /// be pointed at rather than the parent comparing version strings by eye.
  int _latestVersionCode = 0;
  StreamSubscription<AppUpdateConfig>? _updateSub;

  @override
  void initState() {
    super.initState();
    if (Db.ready) {
      _updateSub = AppUpdateRepository.instance.watch().listen((c) {
        if (mounted) setState(() => _latestVersionCode = c.versionCode);
      });
    }
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  /// Which device's data the feature screens show. Null means every device.
  String? _deviceId;

  bool get _live => _familyId != null && Db.ready;

  void _switchTo(Child child, String familyId) {
    if (child.id == _child.id) return;
    setState(() {
      _child = child;
      _familyId = familyId;
      _name = child.name;
      _deviceId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = _child;
    final familyId = _familyId;
    final canEdit = AccessScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _rename,
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // One subscription for the whole page: the profile document is
      // stamped by every device, so its status, version and last error are
      // whichever device reported last. The devices are the truth.
      body: ChildDevices(
        familyId: familyId,
        childId: child.id,
        builder: (context, devices) {
          final faulty = ProfileStatus.faulty(devices);
          final erroring = devices.where((d) => d.hasRecentError).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned: which child you are looking at, and their status. Both
              // scrolled away, so half way down the page there was nothing
              // saying whose data was on screen.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (Db.ready)
                      _ChildSwitcher(
                        currentId: child.id,
                        onSelect: _switchTo,
                      ),
                    _ProfileHeaderCard(
                      name: _name,
                      child: child,
                      devices: devices,
                      faulty: faulty,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.xxl,
                  ),
                  children: [
                  for (final device in erroring) ...[
                    _DeviceIssueCard(device: device),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_live) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Devices',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (canEdit)
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PairDeviceScreen(
                                  familyId: familyId!,
                                  child: child,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add device'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _DeviceList(
                      familyId: familyId!,
                      childId: child.id,
                      devices: devices,
                      selectedId: _deviceId,
                      latestVersionCode: _latestVersionCode,
                      onSelect: (id) => setState(() => _deviceId = id),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Text('Manage', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  // A centered Wrap instead of a grid: with an odd tile count
                  // the last tile sits in the middle rather than hanging left.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final w = (constraints.maxWidth - AppSpacing.sm) / 2;
                      final h = w / 1.15;
                      Widget cell(Widget tile) =>
                          SizedBox(width: w, height: h, child: tile);
                      // A PC cannot report calls or SMS, so those tiles would
                      // open a screen that stays empty for good. Devices
                      // declare what they can report and the tiles follow.
                      final effectiveDeviceId =
                          _deviceId ??
                          (devices.isNotEmpty ? devices.first.id : null);
                      // With one device selected the tiles describe that device
                      // rather than the whole profile.
                      final scope = effectiveDeviceId == null
                          ? devices
                          : devices
                                .where((d) => d.id == effectiveDeviceId)
                                .toList();
                      bool has(String feature) =>
                          DeviceFeature.supportedBy(scope, feature);
                      final selectedPlatform =
                          effectiveDeviceId == null || scope.isEmpty
                          ? null
                          : scope.first.platform;
                      return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      if (has(DeviceFeature.calls))
                        cell(
                          _FeatureTile(
                            icon: Icons.call_rounded,
                            color: AppColors.info,
                            title: 'Call history',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CallHistoryScreen(
                                  childName: _name,
                                  familyId: familyId,
                                  childId: child.id,
                                  deviceId: effectiveDeviceId,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (has(DeviceFeature.sms))
                        cell(
                          _FeatureTile(
                            icon: Icons.sms_rounded,
                            color: AppColors.success,
                            title: 'Messages',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SmsHistoryScreen(
                                  childName: _name,
                                  familyId: familyId,
                                  childId: child.id,
                                  deviceId: effectiveDeviceId,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (has(DeviceFeature.chats))
                        cell(
                          _FeatureTile(
                            mark: const WhatsAppMark(size: 44),
                            icon: Icons.forum_rounded,
                            color: WhatsAppMark.brandGreen,
                            title: 'WhatsApp',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatHistoryScreen(
                                  childName: _name,
                                  familyId: familyId,
                                  childId: child.id,
                                  deviceId: effectiveDeviceId,
                                  platform: selectedPlatform,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (has(DeviceFeature.youtube))
                        cell(
                          _FeatureTile(
                            icon: Icons.smart_display_rounded,
                            color: AppColors.danger,
                            title: 'YouTube',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => YoutubeHistoryScreen(
                                  childName: _name,
                                  familyId: familyId,
                                  childId: child.id,
                                  deviceId: effectiveDeviceId,
                                  platform: selectedPlatform,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (has(DeviceFeature.webHistory))
                        cell(
                          _FeatureTile(
                            icon: Icons.public_rounded,
                            color: AppColors.info,
                            title: 'Web activity',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ActivityScreen(
                                  childName: child.name,
                                  familyId: familyId,
                                  childId: child.id,
                                  deviceId: effectiveDeviceId,
                                  platform: selectedPlatform,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (has(DeviceFeature.appBlocking))
                        cell(
                          _FeatureTile(
                            icon: Icons.apps_rounded,
                            color: AppColors.accent,
                            title: 'App rules',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AppRulesScreen(
                                  childName: _name,
                                  familyId: familyId,
                                  childId: child.id,
                                  deviceId: effectiveDeviceId,
                                  deviceLabel: scope.isEmpty
                                      ? null
                                      : scope.first.label,
                                  platform: selectedPlatform,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (has(DeviceFeature.location))
                        cell(
                          _FeatureTile(
                            icon: Icons.location_on_rounded,
                            color: AppColors.warning,
                            title: 'Location',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LocationScreen(
                                  childName: _name,
                                  familyId: familyId,
                                  childId: child.id,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (canEdit)
                    OutlinedButton.icon(
                      onPressed: () => _confirmDeleteProfile(context),
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: AppColors.danger,
                        size: 18,
                      ),
                      label: const Text(
                        'Delete profile',
                        style: TextStyle(color: AppColors.danger),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.danger.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          focusNode: focus,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            label: 'Save',
          ),
        ],
      ),
    );
    focus.dispose();
    if (newName == null || newName.isEmpty || newName == _name) return;

    if (_live) {
      if (!mounted) return;
      if (!await Net.require(context)) return;
      try {
        await FamilyRepository.instance.renameChild(
          _familyId!,
          _child.id,
          newName,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Couldn\u2019t rename \u2014 ${friendlyError(e)}'),
            ),
          );
        }
        return;
      }
    }
    if (mounted) setState(() => _name = newName);
  }

  Future<void> _confirmDeleteProfile(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Devices must be removed one by one first: deleting a profile under a
    // live installation would leave it enforcing rules nobody can manage.
    if (_live) {
      final devices = await DeviceRepository.instance
          .watch(_familyId!, _child.id)
          .first;
      if (devices.isNotEmpty) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove devices first'),
            content: Text(
              '$_name still has ${devices.length} linked '
              'device${devices.length == 1 ? '' : 's'}. Remove each device '
              '(\u22EE next to it above) before deleting the profile.',
            ),
            actions: [
              DialogConfirmButton(
                onPressed: () => Navigator.pop(ctx),
                label: 'OK',
              ),
            ],
          ),
        );
        return;
      }
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TypedDangerDialog(
        title: 'Delete this profile?',
        warning:
            'This removes $_name\u2019s profile and all saved activity. '
            'This cannot be undone.',
        prompt: 'Type the profile name to confirm:',
        expected: _name,
        actionLabel: 'Delete',
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    if (!await Net.require(context)) return;
    if (!context.mounted) return;

    if (_live) {
      try {
        await Net.withProgress(
          context,
          'Deleting $_name\u2019s profile\u2026',
          () => FamilyRepository.instance.deleteProfile(_familyId!, _child.id),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Couldn\u2019t delete the profile \u2014 ${friendlyError(e)}',
            ),
          ),
        );
        return;
      }
    }
    messenger.showSnackBar(
      SnackBar(content: Text('$_name\u2019s profile was deleted.')),
    );
    navigator.pop();
  }
}

/// The profile at the top of its own page: who this is, what is linked and
/// whether anything needs doing. The app bar only had room for the name.
class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.name,
    required this.child,
    required this.devices,
    required this.faulty,
  });

  final String name;
  final Child child;
  final List<Device> devices;

  /// The device a parent should deal with first, if any.
  final Device? faulty;

  @override
  Widget build(BuildContext context) {
    final worst = ProfileStatus.worst(devices);
    final status = child.effectiveStatus;
    final statusColor = worst?.statusColor ?? status.color;
    final statusLabel = worst?.statusLabel ?? status.label;
    final removed = worst != null
        ? worst.likelyRemoved || worst.removalUnlocked
        : status == ChildStatus.removed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: child.paired
                    ? statusColor
                    : AppColors.borderOf(context),
                width: 2.5,
              ),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: removed ? AppColors.danger : child.avatarColor,
              child: removed
                  ? const Icon(
                      Icons.gpp_bad_rounded,
                      color: Colors.white,
                      size: 26,
                    )
                  : Text(
                      name.trim().isEmpty
                          ? '?'
                          : name.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 21,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                if (!child.paired)
                  Text(
                    'No device linked',
                    style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _HeaderPill(
                        label: statusLabel,
                        color: statusColor,
                        dot: true,
                      ),
                      if (devices.isNotEmpty)
                        _HeaderPill(
                          label: devices.length == 1
                              ? devices.first.label
                              : '${devices.length} devices',
                          color: AppColors.textSecondaryOf(context),
                          icon: devices.length == 1
                              ? devices.first.icon
                              : Icons.devices_rounded,
                        ),
                    ],
                  ),
                // With several devices the pill above is the worst of them, so
                // name which one it is or the parent has to open each in turn.
                if (faulty != null && devices.length > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Needs attention on ${faulty!.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: faulty!.statusColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          if (icon != null) Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceIssueCard extends StatelessWidget {
  const _DeviceIssueCard({required this.device});
  final Device device;

  /// The device reports a raw exception string, which is for diagnosing a
  /// remote device, not something to put in front of a parent.
  static String _plainEnglish(String raw) {
    final e = raw.toLowerCase();
    if (e.contains('permission_denied') || e.contains('permission denied')) {
      return 'The device was refused access to your family\u2019s settings.';
    }
    if (e.contains('unavailable') || e.contains('network')) {
      return 'The device could not reach the internet.';
    }
    if (e.contains('unauthenticated')) {
      return 'The device signed out and needs to be paired again.';
    }
    return 'The device hit an error while syncing.';
  }

  @override
  Widget build(BuildContext context) {
    final at = device.lastErrorAt;
    final ago = at == null ? null : DateTime.now().difference(at);
    final when = ago == null
        ? ''
        : (ago.inMinutes < 60
              ? '${ago.inMinutes} min ago'
              : '${ago.inHours} h ago');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.report_problem_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when.isEmpty
                      ? '${device.label} reported a problem'
                      : '${device.label} reported a problem \u00b7 $when',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _plainEnglish(device.lastError ?? ''),
                  style: TextStyle(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'If protection looks wrong, restart the child device or '
                  're-check its permissions.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal strip of the family's children so a parent can move between
/// them here, instead of going back to the list and picking another.
class _ChildSwitcher extends StatelessWidget {
  const _ChildSwitcher({required this.currentId, required this.onSelect});

  final String currentId;
  final void Function(Child child, String familyId) onSelect;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<({Child child, String familyId})>>(
      stream: FamilyRepository.instance.watchMyChildren(),
      builder: (context, snap) {
        final kids = snap.data ?? const <({Child child, String familyId})>[];
        // Nothing to switch between with a single child.
        if (kids.length < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kids.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) {
                final k = kids[i];
                final selected = k.child.id == currentId;
                return _SwitcherChip(
                  child: k.child,
                  selected: selected,
                  onTap: () => onSelect(k.child, k.familyId),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final Child child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = child.effectiveStatus;
    // Unlinked profiles carry no status colour.
    final dotColor = child.paired ? status.color : AppColors.borderOf(context);
    // A rectangular pill instead of a circular avatar: names were truncating
    // inside the fixed-width circles.
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: Colors.white, width: 1)
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              child.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : AppColors.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The devices attached to this profile, one full-width row each. Squeezing
/// two side by side (or three into circular chips) cut the status and version
/// off exactly when a profile had enough devices for them to matter. Tapping
/// one scopes the feature screens to it.
class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.familyId,
    required this.childId,
    required this.devices,
    this.selectedId,
    this.latestVersionCode = 0,
    required this.onSelect,
  });

  final String familyId;
  final String childId;
  final List<Device> devices;
  final String? selectedId;
  final int latestVersionCode;
  final ValueChanged<String?> onSelect;

  Future<void> _confirmRemove(BuildContext context, Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TypedDangerDialog(
        title: 'Remove this device?',
        warning:
            'Protection and monitoring stop on ${device.label}, and '
            'everything it reported — history, chats, usage — is deleted. The '
            'profile and its other devices stay in place.',
        prompt: 'Type the device name to confirm:',
        expected: device.label,
        actionLabel: 'Remove',
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    if (!await Net.require(context)) return;
    if (!context.mounted) return;
    try {
      await Net.withProgress(
        context,
        'Removing ${device.label}\u2026',
        () => DeviceRepository.instance.revoke(familyId, childId, device.id),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${device.label} was removed.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Couldn\u2019t remove the device \u2014 ${friendlyError(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _confirmRename(BuildContext context, Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: device.label);
    final focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          focusNode: focus,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Device name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            label: 'Save',
          ),
        ],
      ),
    );
    focus.dispose();
    if (newName == null || newName.isEmpty || newName == device.label) return;
    if (!context.mounted) return;
    if (!await Net.require(context)) return;
    try {
      await DeviceRepository.instance.rename(
        familyId,
        childId,
        device.id,
        newName,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Device renamed to $newName.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Couldn\u2019t rename the device \u2014 ${friendlyError(e)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = AccessScope.of(context);
    if (devices.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(
                Icons.smartphone_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'This device will appear here after it next checks in.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // The feature screens always show one device, so pick the first as
    // soon as the list arrives rather than leaving nothing selected.
    if (selectedId == null || devices.every((d) => d.id != selectedId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onSelect(devices.first.id);
      });
    }
    return Column(
      children: [
        for (var i = 0; i < devices.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _DeviceCard(
            device: devices[i],
            selected: devices[i].id == selectedId,
            latestVersionCode: latestVersionCode,
            onTap: () => onSelect(devices[i].id),
            onRename: canEdit
                ? () => _confirmRename(context, devices[i])
                : null,
            onRemove: canEdit
                ? () => _confirmRemove(context, devices[i])
                : null,
          ),
        ],
      ],
    );
  }
}

/// A device as a full-width card: its platform, the parent's name for it, its
/// status and the version it is running. Every one of those is per device, so
/// they must survive a profile that has several.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.onTap,
    this.latestVersionCode = 0,
    this.onRename,
    this.onRemove,
  });

  final Device device;
  final bool selected;
  final int latestVersionCode;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasMenu = onRename != null || onRemove != null;
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sm + 2,
            AppSpacing.sm + 2,
            hasMenu ? 0 : AppSpacing.md,
            AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderOf(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: device.platformColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  device.icon,
                  color: device.platformColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Status and version wrap rather than compete: a long
                    // status used to push the version off the end of the row.
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: device.statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              device.statusLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: device.statusColor,
                              ),
                            ),
                          ],
                        ),
                        if (device.versionLabel.isNotEmpty)
                          Text(
                            device.versionLabel,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        // An OTA is otherwise invisible until it lands.
                        if (latestVersionCode > 0 &&
                            device.appVersionCode > 0 &&
                            device.appVersionCode < latestVersionCode)
                          Text(
                            'Update pending',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                      ],
                    ),
                    if (device.missingProtectionLabels.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Missing: ${device.missingProtectionLabels.join(', ')}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasMenu)
                PopupMenuButton<String>(
                  tooltip: 'Device options',
                  position: PopupMenuPosition.under,
                  onSelected: (v) {
                    if (v == 'rename') onRename?.call();
                    if (v == 'remove') onRemove?.call();
                  },
                  itemBuilder: (_) => [
                    if (onRename != null)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                    if (onRemove != null)
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove'),
                      ),
                  ],
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
    this.mark,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;

  /// Drawn instead of [icon] when the feature has a brand logo.
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              // A wide icon banner rather than a small badge: at tile size a
              // 48px square left a hole in the middle of the card.
              Expanded(
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: mark ?? Icon(icon, color: color, size: 34),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}
