import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A single message bubble in a captured conversation: received on the left,
/// the child's own sent messages on the right.
///
/// Background and text colour are always chosen together per theme — picking
/// only the background and letting the app theme supply the text colour drew
/// near-white text on a pale bubble in dark mode.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.time,
    required this.outgoing,
    this.withTail = true,
  });

  final String text;
  final String time;
  final bool outgoing;

  /// Only the bubble that starts a run from one side gets the pointed corner,
  /// so a burst of messages reads as one block.
  final bool withTail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = outgoing
        ? ChatColors.outgoingOf(isDark)
        : ChatColors.incomingOf(isDark);
    final fg = ChatColors.textOf(isDark);
    final meta = ChatColors.metaOf(isDark);
    const round = Radius.circular(12);
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: outgoing ? 52 : 12,
          right: outgoing ? 12 : 52,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The pointed tail sits just outside the bubble on the side it
            // came from — only on the first bubble of a run, like the
            // original app.
            if (withTail)
              Positioned(
                top: 0,
                left: outgoing ? null : -7,
                right: outgoing ? -7 : null,
                child: CustomPaint(
                  size: const Size(8, 12),
                  painter: _BubbleTail(color: bg, outgoing: outgoing),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: (withTail && !outgoing) ? Radius.zero : round,
                  topRight: (withTail && outgoing) ? Radius.zero : round,
                  bottomLeft: round,
                  bottomRight: round,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
              // The time sits on the same last line as the text when it fits,
              // and drops below when it doesn't — the layout the original app
              // uses.
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontSize: 16, height: 1.35, color: fg),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: TextStyle(
                                color: meta, fontSize: 11, height: 1.1),
                          ),
                        if (outgoing) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.done_all_rounded,
                              size: 15, color: ChatColors.tick),
                        ],
                      ],
                    ),
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

/// The curved triangle poking out of a bubble's top corner.
class _BubbleTail extends CustomPainter {
  const _BubbleTail({required this.color, required this.outgoing});
  final Color color;
  final bool outgoing;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (outgoing) {
      path
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..quadraticBezierTo(w * 0.55, h * 0.45, 0, h);
    } else {
      path
        ..moveTo(w, 0)
        ..lineTo(0, 0)
        ..quadraticBezierTo(w * 0.45, h * 0.45, w, h);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTail old) =>
      old.color != color || old.outgoing != outgoing;
}

/// The conversation backdrop: the messenger's wallpaper colour overlaid with
/// its faint repeating doodle, drawn procedurally so no artwork is bundled.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: ChatColors.wallpaperOf(isDark),
      child: CustomPaint(
        painter: _DoodlePainter(color: ChatColors.doodleOf(isDark)),
        child: child,
      ),
    );
  }
}

/// Sparse grid of tiny motifs (rings, plus signs, dots, sparks, squiggles),
/// deterministic per cell so it never shimmers on rebuild.
class _DoodlePainter extends CustomPainter {
  const _DoodlePainter({required this.color});
  final Color color;

  static const double _cell = 56;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;

    for (var row = 0; row * _cell < size.height; row++) {
      for (var col = 0; col * _cell < size.width; col++) {
        final h = _hash(row, col);
        // Offset the motif inside its cell so the grid doesn't read as one.
        final dx = col * _cell + 12 + (h >> 3) % 28;
        final dy = row * _cell + 12 + (h >> 8) % 28 + (col.isOdd ? 14 : 0);
        final c = Offset(dx.toDouble(), dy.toDouble());
        switch (h % 6) {
          case 0:
            canvas.drawCircle(c, 5.5, stroke);
          case 1:
            canvas.drawCircle(c, 2.0, fill);
          case 2: // plus
            canvas.drawLine(c - const Offset(4.5, 0), c + const Offset(4.5, 0), stroke);
            canvas.drawLine(c - const Offset(0, 4.5), c + const Offset(0, 4.5), stroke);
          case 3: // four-point spark
            canvas.drawLine(c - const Offset(4, 4), c + const Offset(4, 4), stroke);
            canvas.drawLine(c - const Offset(-4, 4), c + const Offset(-4, 4), stroke);
          case 4: // squiggle
            final p = Path()
              ..moveTo(c.dx - 6, c.dy)
              ..quadraticBezierTo(c.dx - 2, c.dy - 6, c.dx + 1, c.dy)
              ..quadraticBezierTo(c.dx + 4, c.dy + 6, c.dx + 8, c.dy);
            canvas.drawPath(p, stroke);
          case 5: // rounded square
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: c, width: 8, height: 8),
                  const Radius.circular(2.5)),
              stroke,
            );
        }
      }
    }
  }

  static int _hash(int row, int col) {
    var h = row * 73856093 ^ col * 19349663;
    h = (h ^ (h >> 13)) * 0x5BD1E995;
    return (h ^ (h >> 15)) & 0x7FFFFFFF;
  }

  @override
  bool shouldRepaint(_DoodlePainter old) => old.color != color;
}

/// The pale-yellow pinned notice at the top of a conversation — the slot the
/// original app uses for its encryption note. Here it explains monitoring.
class ThreadNotice extends StatelessWidget {
  const ThreadNotice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = ChatColors.noticeTextOf(isDark);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ChatColors.noticeOf(isDark),
          borderRadius: BorderRadius.circular(8),
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.lock_rounded, size: 11, color: fg),
                ),
              ),
              TextSpan(text: text),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: fg, fontSize: 12, height: 1.35),
        ),
      ),
    );
  }
}

/// The centred day separator in a conversation. Also used for the "load
/// earlier" control so it sits in the thread instead of looking like a button.
class DayChip extends StatelessWidget {
  const DayChip({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ChatColors.dateChipOf(isDark),
        borderRadius: BorderRadius.circular(8),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ChatColors.metaOf(isDark),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: chip,
    );
  }
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// The full date ("21 August 2026") as a conversation separator. Always the
/// date — never "Today"/"Yesterday" — so a captured chat reads unambiguously
/// no matter when the parent opens it.
String dayLabel(DateTime t) => '${t.day} ${_monthNames[t.month - 1]} ${t.year}';
