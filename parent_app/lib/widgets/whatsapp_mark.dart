import 'package:flutter/material.dart';

/// WhatsApp's mark, shown wherever captured WhatsApp data is surfaced.
class WhatsAppMark extends StatelessWidget {
  const WhatsAppMark({super.key, this.size = 24});

  static const brandGreen = Color(0xFF25D366);

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/whatsapp.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
