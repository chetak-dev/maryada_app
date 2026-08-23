import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/device_repository.dart';
import '../../data/family_repository.dart';
import '../../models/child.dart';
import '../../models/device.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
        children: [
          if (Db.ready)
            _ChildSwitcher(currentId: child.id, onSelect: _switchTo),
          if (child.hasRecentError) ...[
            _DeviceIssueCard(child: child),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_live) ...[
            Row(
              children: [
                Expanded(
                  child: Text('Devices', style: theme.textTheme.titleMedium),
                ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PairDeviceScreen(
                            familyId: familyId!, child: child),
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
              selectedId: _deviceId,
              onSelect: (id) => setState(() => _deviceId = id),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Manage', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // A centered Wrap instead of a grid: with an odd tile count the last
          // tile sits in the middle rather than hanging left.
          LayoutBuilder(
            builder: (context, constraints) {
              final w = (constraints.maxWidth - AppSpacing.sm) / 2;
              final h = w / 1.15;
              Widget cell(Widget tile) =>
                  SizedBox(width: w, height: h, child: tile);
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
              cell(_FeatureTile(
                icon: Icons.call_rounded,
                color: AppColors.info,
                title: 'Call history',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallHistoryScreen(
                        childName: _name,
                        familyId: familyId,
                        childId: child.id,
                        deviceId: _deviceId),
                  ),
                ),
              )),
              cell(_FeatureTile(
                icon: Icons.sms_rounded,
                color: AppColors.success,
                title: 'Messages',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SmsHistoryScreen(
                        childName: _name,
                        familyId: familyId,
                        childId: child.id,
                        deviceId: _deviceId),
                  ),
                ),
              )),
              cell(_FeatureTile(
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
                        deviceId: _deviceId),
                  ),
                ),
              )),
              cell(_FeatureTile(
                icon: Icons.smart_display_rounded,
                color: AppColors.danger,
                title: 'YouTube',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => YoutubeHistoryScreen(
                        childName: _name,
                        familyId: familyId,
                        childId: child.id,
                        deviceId: _deviceId),
                  ),
                ),
              )),
              cell(_FeatureTile(
                icon: Icons.public_rounded,
                color: AppColors.info,
                title: 'Web activity',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ActivityScreen(
                        childName: child.name,
                        familyId: familyId,
                        childId: child.id,
                        deviceId: _deviceId),
                  ),
                ),
              )),
              cell(_FeatureTile(
                icon: Icons.apps_rounded,
                color: AppColors.accent,
                title: 'App rules',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AppRulesScreen(
                        childName: _name,
                        familyId: familyId,
                        childId: child.id),
                  ),
                ),
              )),
              cell(_FeatureTile(
                icon: Icons.location_on_rounded,
                color: AppColors.warning,
                title: 'Location',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LocationScreen(
                        childName: _name,
                        familyId: familyId,
                        childId: child.id),
                  ),
                ),
              )),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (canEdit)
            OutlinedButton.icon(
              onPressed: () => _confirmDeleteProfile(context),
              icon: const Icon(Icons.delete_forever_rounded,
                  color: AppColors.danger, size: 18),
              label: const Text('Delete profile',
                  style: TextStyle(color: AppColors.danger)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppColors.danger.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              ),
            ),
        ],
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
        await FamilyRepository.instance
            .renameChild(_familyId!, _child.id, newName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\u2019t rename â€” ${friendlyError(e)}')),
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

    // Devices must be removed one by one first â€” deleting a profile under a
    // live installation would leave it enforcing rules nobody can manage.
    if (_live) {
      final devices =
          await DeviceRepository.instance.watch(_familyId!, _child.id).first;
      if (devices.isNotEmpty) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove devices first'),
            content: Text(
              '$_name still has ${devices.length} linked '
              'device${devices.length == 1 ? '' : 's'}. Remove each device '
              '(â‹® next to it above) before deleting the profile.',
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
        warning: 'This removes $_nameâ€™s profile and all saved activity. '
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
          'Deleting $_nameâ€™s profileâ€¦',
          () => FamilyRepository.instance.deleteProfile(_familyId!, _child.id),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
              content: Text(
                  'Couldn\u2019t delete the profile â€” ${friendlyError(e)}')),
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

class _DeviceIssueCard extends StatelessWidget {
  const _DeviceIssueCard({required this.child});
  final Child child;

  /// The device reports a raw exception string, which is for diagnosing a
  /// remote device â€” not something to put in front of a parent.
  static String _plainEnglish(String raw) {
    final e = raw.toLowerCase();
    if (e.contains('permission_denied') || e.contains('permission denied')) {
      return 'The device was refused access to your familyâ€™s settings.';
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
    final at = child.lastErrorAt;
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
          const Icon(Icons.report_problem_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when.isEmpty
                      ? 'The device reported a problem'
                      : 'The device reported a problem Â· $when',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _plainEnglish(child.lastError ?? ''),
                  style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  'If protection looks wrong, restart the child device or '
                  're-check its permissions.',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 12),
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
    final dotColor =
        child.paired ? status.color : AppColors.borderOf(context);
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

/// The devices attached to this profile, side by side so more devices widen
/// the strip instead of pushing the rest of the page down. Tapping one scopes
/// the feature screens to it.
class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.familyId,
    required this.childId,
    this.selectedId,
    required this.onSelect,
  });

  final String familyId;
  final String childId;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  Future<void> _confirmRemove(BuildContext context, Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TypedDangerDialog(
        title: 'Remove this device?',
        warning: 'Protection and monitoring stop on ${device.label}, and '
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
        'Removing ${device.label}â€¦',
        () => DeviceRepository.instance.revoke(familyId, childId, device.id),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${device.label} was removed.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content:
                Text('Couldn\u2019t remove the device â€” ${friendlyError(e)}')),
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
    );    focus.dispose();
    if (newName == null || newName.isEmpty || newName == device.label) return;
    if (!context.mounted) return;
    if (!await Net.require(context)) return;
    try {
      await DeviceRepository.instance
          .rename(familyId, childId, device.id, newName);
      messenger.showSnackBar(
        SnackBar(content: Text('Device renamed to $newName.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content:
                Text('Couldn\u2019t rename the device â€” ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = AccessScope.of(context);
    return StreamBuilder<List<Device>>(
      stream: DeviceRepository.instance.watch(familyId, childId),
      builder: (context, snap) {
        final devices = snap.data ?? const <Device>[];
        if (devices.isEmpty) {
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.smartphone_rounded,
                      color: AppColors.textMuted, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      snap.connectionState == ConnectionState.waiting
                          ? 'Loading devicesâ€¦'
                          : 'This device will appear here after it next checks in.',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
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
        Widget tile(Device d) => _DeviceCard(
              device: d,
              selected: d.id == selectedId,
              compact: devices.length > 1,
              onTap: () => onSelect(d.id),
              onRename: canEdit ? () => _confirmRename(context, d) : null,
              onRemove: canEdit ? () => _confirmRemove(context, d) : null,
            );
        // One or two devices read better as full cards; beyond that they'd be
        // too narrow, so they become a scrollable strip of chips.
        if (devices.length <= 2) {
          return Row(
            children: [
              for (var i = 0; i < devices.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: tile(devices[i])),
              ],
            ],
          );
        }
        return SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: devices.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) {
              final d = devices[i];
              return _DeviceTile(
                device: d,
                selected: d.id == selectedId,
                onTap: () => onSelect(d.id),
                onRename: canEdit ? () => _confirmRename(context, d) : null,
                onRemove: canEdit ? () => _confirmRemove(context, d) : null,
              );
            },
          ),
        );
      },
    );
  }
}

/// A device shown as a full card â€” used while the profile has one or two of
/// them, where the name and status fit properly instead of being squeezed
/// under a circle.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.onRename,
    this.onRemove,
  });

  final Device device;
  final bool selected;

  /// Two side by side: the same card with less room to spend.
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasMenu = onRename != null || onRemove != null;
    final iconSize = compact ? 40.0 : 46.0;
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.sm + 2, AppSpacing.sm + 2, hasMenu ? 0 : AppSpacing.md,
              AppSpacing.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.borderOf(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: device.platformColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(device.icon,
                    color: device.platformColor, size: compact ? 20 : 24),
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
                        fontSize: compact ? 13.5 : 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
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
                        Flexible(
                          child: Text(
                            device.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: device.statusColor,
                            ),
                          ),
                        ),
                        if (device.versionLabel.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Text(
                            '· ${device.versionLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                          value: 'rename', child: Text('Rename')),
                    if (onRemove != null)
                      const PopupMenuItem(
                          value: 'remove', child: Text('Remove')),
                  ],
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 18, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onTap,
    this.onRename,
    this.onRemove,
  });

  final Device device;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final color = device.statusColor;
    final hasMenu = onRename != null || onRemove != null;
    // A circular chip like the family strip, sized so three fit across and the
    // rest scroll sideways.
    return SizedBox(
      width: 96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            onLongPress: onRemove,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              selected ? AppColors.primary : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: device.platformColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(device.icon,
                            color: device.platformColor, size: 24),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  device.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          if (hasMenu)
            Positioned(
              top: -4,
              right: -6,
              child: PopupMenuButton<String>(
                tooltip: 'Device options',
                position: PopupMenuPosition.under,
                onSelected: (v) {
                  if (v == 'rename') onRename?.call();
                  if (v == 'remove') onRemove?.call();
                },
                itemBuilder: (_) => [
                  if (onRename != null)
                    const PopupMenuItem(
                        value: 'rename', child: Text('Rename')),
                  if (onRemove != null)
                    const PopupMenuItem(
                        value: 'remove', child: Text('Remove')),
                ],
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.more_vert_rounded,
                      size: 18, color: AppColors.textMuted),
                ),
              ),
            ),
        ],
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
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}
