import 'package:flutter/material.dart';

import '../models/child.dart';
import '../screens/child_detail/child_detail_screen.dart';
import '../theme/tokens.dart';
import 'status_pill.dart';

/// One child's summary row: avatar, name, device, status and app version.
/// Shared by the dashboard summary and the full Children list.
class ChildCard extends StatelessWidget {
  const ChildCard({
    super.key,
    required this.child,
    this.familyId,
    this.latestVersionCode = 0,
  });

  final Child child;
  final String? familyId;
  final int latestVersionCode;

  Widget _versionChip() {
    final hasVersion = child.appVersionCode > 0;
    if (!hasVersion && latestVersionCode == 0) return const SizedBox.shrink();
    final outdated =
        latestVersionCode > 0 && child.appVersionCode < latestVersionCode;
    // Only the outdated case is worth words; an up-to-date device just shows
    // its version, which has to fit beside the name.
    final label = outdated
        ? 'Update'
        : (child.appVersionName?.isNotEmpty == true
            ? 'v${child.appVersionName}'
            : (hasVersion ? 'b${child.appVersionCode}' : '?'));
    final color = outdated ? AppColors.warning : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              outdated
                  ? Icons.system_update_rounded
                  : Icons.smartphone_rounded,
              size: 11,
              color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) =>
                  ChildDetailScreen(child: child, familyId: familyId)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: child.avatarColor,
                child: Text(
                  child.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            child.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _versionChip(),
                      ],
                    ),
                    const SizedBox(height: 3),
                    StatusPill(
                      label: child.effectiveStatus.label,
                      color: child.effectiveStatus.color,
                      icon: child.effectiveStatus.icon,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
