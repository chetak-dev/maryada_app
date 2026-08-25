import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_update_repository.dart';
import '../../data/db.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';

/// Lets a site admin publish an app update: the newest version code + APK URL.
/// Child devices poll `appConfig/kid` and install silently (Device Owner); the
/// parent app polls `appConfig/parent` and offers the download, since an
/// ordinary phone can never install silently.
class PublishUpdateScreen extends StatefulWidget {
  const PublishUpdateScreen({super.key, this.target = AppUpdateRepository.kidDoc});

  /// Which manifest this screen edits.
  final String target;

  @override
  State<PublishUpdateScreen> createState() => _PublishUpdateScreenState();
}

class _PublishUpdateScreenState extends State<PublishUpdateScreen> {
  final _versionController = TextEditingController();
  final _urlController = TextEditingController();
  final _shaController = TextEditingController();
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  int _currentVersion = 0;

  bool get _live => Db.ready;
  bool get _isParent => widget.target == AppUpdateRepository.parentDoc;
  bool get _isWindows => widget.target == AppUpdateRepository.windowsDoc;

  String get _fileLabel => _isWindows ? 'Installer' : 'APK';

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
      final c = await AppUpdateRepository.instance.load(widget.target);
      if (!mounted) return;
      setState(() {
        _enabled = c.enabled;
        _currentVersion = c.versionCode;
        if (c.versionCode > 0) _versionController.text = '${c.versionCode}';
        _urlController.text = c.url;
        _shaController.text = c.sha256;
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
    _shaController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.of(context);
    final version = int.tryParse(_versionController.text.trim());
    final url = _urlController.text.trim();
    final sha = _shaController.text.trim().toLowerCase();
    if (version == null || version <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a valid version code (a number).')),
      );
      return;
    }
    if (!url.startsWith('https://')) {
      messenger.showSnackBar(
        SnackBar(content: Text('$_fileLabel URL must start with https://')),
      );
      return;
    }
    // Windows PCs refuse an update they cannot check, so publishing one
    // without a checksum would just stall the whole fleet silently.
    if (_isWindows && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Enter the installer SHA-256 (64 hex characters).')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AppUpdateRepository.instance.publish(
        AppUpdateConfig(
            enabled: _enabled, versionCode: version, url: url, sha256: sha),
        widget.target,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _currentVersion = version;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isParent
              ? 'Published. Parents are offered the update next time they open the app.'
              : 'Update published. Devices update within ~3 hours.'),
        ),
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
      appBar: AppBar(
          title: Text(_isParent
              ? 'Publish parent update'
              : _isWindows
                  ? 'Publish PC update'
                  : 'Publish app update')),
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
                      _isParent
                          ? 'Offer a new build of this parent app. Host the '
                              'APK at an https URL and set the version code to '
                              'match it. Parents get a prompt and install it '
                              'themselves — an ordinary phone cannot install '
                              'silently.'
                          : _isWindows
                              ? 'Push a new build to every child PC. Host the '
                                  'signed installer at an https URL and paste '
                                  'its SHA-256 below — a PC refuses any update '
                                  'it cannot verify.'
                              : 'Push a new build to all child devices. Host the '
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
                  decoration: InputDecoration(
                    labelText: '$_fileLabel download URL (https)',
                    hintText: _isWindows
                      ? 'https://\u2026/Maryada-Windows-1.0.5.bin'
                        : 'https://\u2026/app-release.apk',
                    helperText: _isWindows
                      ? 'A signed EXE may be hosted with a .bin extension.'
                      : null,
                  ),
                ),
                if (_isWindows) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _shaController,
                    decoration: const InputDecoration(
                      labelText: 'Installer SHA-256',
                      hintText: '64 hex characters',
                      helperText:
                          'PowerShell: Get-FileHash .\\Maryada-Setup.exe',
                    ),
                  ),
                ],
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
