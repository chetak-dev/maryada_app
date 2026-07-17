import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/sms_history_repository.dart';
import '../../theme/tokens.dart';

/// Shows a child's SMS history (received + sent) reported by the child device.
class SmsHistoryScreen extends StatefulWidget {
  const SmsHistoryScreen({
    super.key,
    required this.childName,
    this.familyId,
    this.childId,
  });

  final String childName;
  final String? familyId;
  final String? childId;

  @override
  State<SmsHistoryScreen> createState() => _SmsHistoryScreenState();
}

class _SmsHistoryScreenState extends State<SmsHistoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Messages · ${widget.childName}')),
      body: !_live
          ? const _Empty(text: 'Connect a device to see its text messages.')
          : Column(
              children: [
                _SearchBox(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
                Expanded(
                  child: StreamBuilder<List<SmsMessage>>(
                    stream: SmsHistoryRepository.instance
                        .watch(widget.familyId!, widget.childId!),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      var msgs = snap.data ?? const <SmsMessage>[];
                      if (msgs.isEmpty) {
                        return const _Empty(
                          text:
                              'No messages yet — they appear once the child device syncs.',
                        );
                      }
                      if (_query.isNotEmpty) {
                        msgs = msgs
                            .where((m) =>
                                m.address.toLowerCase().contains(_query) ||
                                m.body.toLowerCase().contains(_query))
                            .toList();
                      }
                      if (msgs.isEmpty) {
                        return const _Empty(
                            text: 'No messages match your search.');
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                            AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
                        itemCount: msgs.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _SmsTile(msg: msgs[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// Search field to filter messages by sender/number or text.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search messages or sender',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SmsTile extends StatelessWidget {
  const _SmsTile({required this.msg});
  final SmsMessage msg;

  static String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final time = '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
    return sameDay ? time : '${t.day}/${t.month} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final sent = msg.isSent;
    final color = sent ? AppColors.primary : AppColors.success;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sent ? Icons.north_east_rounded : Icons.south_west_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    msg.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Text(sent ? 'Sent' : 'Received',
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(msg.body, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(_when(msg.at),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
