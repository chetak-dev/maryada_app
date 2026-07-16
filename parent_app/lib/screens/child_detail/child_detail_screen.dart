import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../models/child.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_pill.dart';
import '../activity/activity_screen.dart';
import '../app_rules/app_rules_screen.dart';
import '../call_history/call_history_screen.dart';
import '../chat_history/chat_history_screen.dart';
import '../location/location_screen.dart';
import '../sms_history/sms_history_screen.dart';
import '../youtube_history/youtube_history_screen.dart';
/// Per-child control center: status, quick actions and the per-device feature
/// areas. UI shell with placeholder actions; backend wiring comes later.
class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({super.key, required this.child, this.familyId});

  final Child child;
  final String? familyId;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  late String _name = widget.child.name;

  bool get _live => widget.familyId != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = widget.child;
    final familyId = widget.familyId;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
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
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          _HeaderCard(child: child, name: _name),
          const SizedBox(height: AppSpacing.lg),
          Text('Manage', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                _FeatureTile(
                  icon: Icons.location_on_rounded,
                  color: AppColors.warning,
                  title: 'Location & places',
                  subtitle: 'Live map, history, geofences',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocationScreen(
                          childName: _name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _FeatureTile(
                  icon: Icons.insights_rounded,
                  color: AppColors.danger,
                  title: 'Activity',
                  subtitle: 'Screen time & most-used apps',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActivityScreen(
                          childName: child.name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _FeatureTile(
                  icon: Icons.apps_rounded,
                  color: AppColors.accent,
                  title: 'App rules',
                  subtitle: 'Block apps, per-app limits, banking mode',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppRulesScreen(
                          childName: _name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _FeatureTile(
                  icon: Icons.call_rounded,
                  color: AppColors.info,
                  title: 'Call history',
                  subtitle: 'Recent incoming & outgoing calls',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CallHistoryScreen(
                          childName: _name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _FeatureTile(
                  icon: Icons.sms_rounded,
                  color: AppColors.accent,
                  title: 'Messages',
                  subtitle: 'Text (SMS) history',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SmsHistoryScreen(
                          childName: _name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _FeatureTile(
                  icon: Icons.forum_rounded,
                  color: AppColors.primary,
                  title: 'Chats',
                  subtitle: 'WhatsApp messages',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatHistoryScreen(
                          childName: _name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _FeatureTile(
                  icon: Icons.smart_display_rounded,
                  color: AppColors.danger,
                  title: 'YouTube',
                  subtitle: 'Watched videos',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => YoutubeHistoryScreen(
                          childName: _name,
                          familyId: familyId,
                          childId: child.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.link_off_rounded, color: AppColors.danger),
            label: const Text('Remove device',
                style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _name) return;

    if (_live) {
      try {
        await FamilyRepository.instance
            .renameChild(widget.familyId!, widget.child.id, newName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\u2019t rename: $e')),
          );
        }
        return;
      }
    }
    if (mounted) setState(() => _name = newName);
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          'This unlinks $_name\u2019s device and stops protection. '
          'You can pair it again later.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_live) {
      try {
        await FamilyRepository.instance
            .removeChild(widget.familyId!, widget.child.id);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Couldn\u2019t remove device: $e')),
        );
        return;
      }
    }
    messenger.showSnackBar(
      SnackBar(content: Text('$_name\u2019s device was removed.')),
    );
    navigator.pop();
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.child, required this.name});
  final Child child;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: child.avatarColor,
              child: Text(
                child.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 26,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    child.deviceModel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  StatusPill(
                    label: child.effectiveStatus.label,
                    color: child.effectiveStatus.color,
                    icon: child.effectiveStatus.icon,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title:
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: onTap ?? () {},
    );
  }
}
