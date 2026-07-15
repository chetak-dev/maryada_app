import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/rules_repository.dart';
import '../../models/screen_time_rule.dart';
import '../../theme/tokens.dart';

/// Interactive Screen-time editor: instant pause, daily limit and a bedtime
/// (downtime) window. Persists to Firestore when [familyId] is set and Firebase
/// is connected; otherwise edits local demo state.
class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({super.key, this.childName, this.familyId});

  final String? childName;
  final String? familyId;

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> {
  ScreenTimeRule _rule = ScreenTimeRule();
  bool _dirty = false;
  bool _loading = false;
  bool _saving = false;

  bool get _live => widget.familyId != null && Db.ready;

  @override
  void initState() {
    super.initState();
    if (_live) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rule =
          await RulesRepository.instance.watchScreenTime(widget.familyId!).first;
      if (!mounted) return;
      setState(() {
        _rule = rule;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _update(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
    });
  }

  TimeOfDay _toTod(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTod(isStart ? _rule.bedtimeStart : _rule.bedtimeEnd),
    );
    if (picked == null) return;
    _update(() {
      final mins = picked.hour * 60 + picked.minute;
      if (isStart) {
        _rule.bedtimeStart = mins;
      } else {
        _rule.bedtimeEnd = mins;
      }
    });
  }

  Future<void> _save() async {
    if (_live) {
      setState(() => _saving = true);
      try {
        await RulesRepository.instance.setScreenTime(widget.familyId!, _rule);
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn’t save: $e')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
    } else {
      setState(() => _dirty = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screen-time rules saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.childName == null
        ? 'Screen time'
        : 'Screen time · ${widget.childName}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
              children: [
                _PauseCard(
                  paused: _rule.paused,
                  onChanged: (v) => _update(() => _rule.paused = v),
                ),
                const SizedBox(height: AppSpacing.md),
                _BedtimeCard(
                  enabled: _rule.bedtimeEnabled,
                  startLabel: _toTod(_rule.bedtimeStart).format(context),
                  endLabel: _toTod(_rule.bedtimeEnd).format(context),
                  onToggle: (v) => _update(() => _rule.bedtimeEnabled = v),
                  onPickStart: () => _pickTime(true),
                  onPickEnd: () => _pickTime(false),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton(
            onPressed: (_dirty && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save changes'),
          ),
        ),
      ),
    );
  }
}

class _PauseCard extends StatelessWidget {
  const _PauseCard({required this.paused, required this.onChanged});
  final bool paused;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: paused ? AppColors.danger.withValues(alpha: 0.06) : null,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        secondary: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (paused ? AppColors.danger : AppColors.primary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            paused ? Icons.pause_circle_filled_rounded : Icons.pause_circle_outline_rounded,
            color: paused ? AppColors.danger : AppColors.primary,
          ),
        ),
        title: const Text('Pause device now',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(paused
            ? 'Device is paused — apps and internet are locked.'
            : 'Instantly lock the device until you turn this off.'),
        value: paused,
        onChanged: onChanged,
      ),
    );
  }
}

class _BedtimeCard extends StatelessWidget {
  const _BedtimeCard({
    required this.enabled,
    required this.startLabel,
    required this.endLabel,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final bool enabled;
  final String startLabel;
  final String endLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            secondary: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.bedtime_rounded, color: AppColors.primary),
            ),
            title: const Text('Bedtime',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Lock the device overnight.'),
            value: enabled,
            onChanged: onToggle,
          ),
          if (enabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: _TimeField(
                        label: 'From', value: startLabel, onTap: onPickStart),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _TimeField(
                        label: 'Until', value: endLabel, onTap: onPickEnd),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
