import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/device_repository.dart';
import '../models/device.dart';

/// Subscribes to one child's devices and hands them to [builder].
///
/// Every device also stamps its state onto the profile document, so the last
/// one to report wins there. Anything that must be true of the *profile* —
/// its status, its version, whether something needs attention — has to be
/// worked out from the devices themselves.
class ChildDevices extends StatefulWidget {
  const ChildDevices({
    super.key,
    required this.familyId,
    required this.childId,
    required this.builder,
  });

  final String? familyId;
  final String childId;
  final Widget Function(BuildContext context, List<Device> devices) builder;

  @override
  State<ChildDevices> createState() => _ChildDevicesState();
}

class _ChildDevicesState extends State<ChildDevices> {
  late Stream<List<Device>> _stream = _open();

  Stream<List<Device>> _open() {
    final familyId = widget.familyId;
    if (!Db.ready || familyId == null || familyId.isEmpty) {
      return const Stream<List<Device>>.empty();
    }
    return DeviceRepository.instance.watch(familyId, widget.childId);
  }

  @override
  void didUpdateWidget(covariant ChildDevices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId ||
        oldWidget.childId != widget.childId) {
      _stream = _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Device>>(
      stream: _stream,
      builder: (context, snap) =>
          widget.builder(context, snap.data ?? const <Device>[]),
    );
  }
}
