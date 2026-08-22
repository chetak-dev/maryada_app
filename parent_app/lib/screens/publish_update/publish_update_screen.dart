import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_update_repository.dart';
import '../../data/db.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';

/// Lets a parent publish an app update: set the newest version code + APK URL
/// that the child devices poll and install silently (Device Owner). Edits the
/// `appConfig/kid` manifest so you don't need the Firebase console.
class PublishUpdateScreen extends StatefulWidget {
  const PublishUpdateScreen({super.key});

  @override
  State<PublishUpdateScreen> createState() => _PublishUpdateScreenState();
}

class _PublishUpdateScreenState extends State<PublishUpdateScreen> {
  final _versionController = TextEditingController();
  final _urlController = TextEditingController();
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  int _currentVersion = 0;

  bool get _live => Db.ready;

  @override
  void initState() {
    super.initState();
    if (_live) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final c = await AppUpdateRepository.instance.watch().first;
      if (!mounted) return;
      setState(() {
        _enabled = c.enabled;
        _currentVersion = c.versionCode;
        if (c.versionCode > 0) _versionController.text = '${c.versionCode}';
        _urlController.text = c.url;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _versionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.of(context);
    final version = int.tryParse(_versionController.text.trim());
    final url = _urlController.text.trim();
    if (version == null || version <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a valid version code (a number).')),
      );
      return;
    }
    if (!url.startsWith('https://')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('APK URL must start with https://')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AppUpdateRepository.instance.publish(
        AppUpdateConfig(enabled: _enabled, versionCode: version, url: url),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _currentVersion = version;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Update published. Devices update within ~3 hours.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn’t publish — ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Publish app update')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
              children: [
                Card(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Push a new build to all child devices. Host the '
                      'release-signed APK at an https URL, paste it below, and '
                      'set the version code to match the new build. '
                      'Device-Owner devices install it silently.',
                      style:
                          TextStyle(color: AppColors.textPrimaryOf(context)),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_currentVersion > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      'Currently published version code: $_currentVersion',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                Card(
                  child: SwitchListTile(
                    title: const Text('Updates enabled'),
                    subtitle: const Text(
                        'Turn off to pause rollouts without clearing the URL.'),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _versionController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'New version code',
                    hintText: 'e.g. 2',
                    helperText: 'Must be higher than the build on the devices.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'APK download URL (https)',
                    hintText: 'https://\u2026/app-release.apk',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _saving ? null : _publish,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(_saving ? 'Publishing\u2026' : 'Publish update'),
                ),
              ],
            ),
    );
  }
}
