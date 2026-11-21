import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ini_storage.dart';
import 'win32_bridge.dart';

/// Sleek RocketDock Aero analog clock painted crisply at any DPI.
class ClockDockletIcon extends StatelessWidget {
  final DateTime now;
  final double size;

  const ClockDockletIcon({super.key, required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ClockFacePainter(now)),
      ),
    );
  }
}

class _ClockFacePainter extends CustomPainter {
  final DateTime now;

  _ClockFacePainter(this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.45;

    // Soft ambient shadow
    canvas.drawCircle(
      center.translate(0, size.height * 0.04),
      r,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Brushed aluminum outer ring
    final ringRect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE2E8F0), Color(0xFF64748B), Color(0xFF1E293B)],
        ).createShader(ringRect),
    );

    // Inner dial
    canvas.drawCircle(
      center,
      r * 0.86,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.0,
          colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
        ).createShader(ringRect),
    );

    // Hour markers
    for (var i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;
      final isQuarter = i % 3 == 0;
      final outer = Offset(
        center.dx + math.cos(angle) * r * 0.76,
        center.dy + math.sin(angle) * r * 0.76,
      );
      final inner = Offset(
        center.dx + math.cos(angle) * r * (isQuarter ? 0.56 : 0.66),
        center.dy + math.sin(angle) * r * (isQuarter ? 0.56 : 0.66),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isQuarter ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)
          ..strokeWidth = isQuarter ? size.width * 0.036 : size.width * 0.02
          ..strokeCap = StrokeCap.round,
      );
    }

    final sec = now.second.toDouble();
    final min = now.minute + sec / 60;
    final hr = (now.hour % 12) + min / 60;

    void drawHand(double deg, double len, double stroke, Color color) {
      final rad = (deg - 90) * math.pi / 180;
      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(rad) * r * len,
          center.dy + math.sin(rad) * r * len,
        ),
        Paint()
          ..color = color
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    drawHand(hr * 30, 0.44, size.width * 0.052, const Color(0xFF0F172A));
    drawHand(min * 6, 0.66, size.width * 0.036, const Color(0xFF1E293B));
    drawHand(sec * 6, 0.72, size.width * 0.022, const Color(0xFFE11D48));
    canvas.drawCircle(center, size.width * 0.042, Paint()..color = const Color(0xFFE11D48));
  }

  @override
  bool shouldRepaint(_ClockFacePainter old) => old.now.second != now.second;
}

/// Sleek Aero Glass Recycle Bin (Empty vs Full with paper sheets inside, clean badge).
class RecycleBinDockletIcon extends StatelessWidget {
  final RecycleBinInfo info;
  final DockItemModel item;
  final double size;
  final FilterQuality quality;

  const RecycleBinDockletIcon({
    super.key,
    required this.info,
    required this.item,
    required this.size,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = info.itemCount > 0;
    final customPath = isFull ? (item.iconPathAlt ?? item.iconPath) : item.iconPath;

    Widget visual;
    if (safeFileExists(customPath)) {
      visual = Image(
        image: ResizeImage(FileImage(File(customPath!)), width: 160),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: quality,
        gaplessPlayback: true,
      );
    } else {
      visual = RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _AeroTrashPainter(isFull: isFull)),
        ),
      );
    }

    if (!isFull) return visual;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        visual,
        Positioned(
          right: -1,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xE60284C7),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1),
            ),
            child: Text(
              info.itemCount > 99 ? '99+' : '${info.itemCount}',
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.05,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AeroTrashPainter extends CustomPainter {
  final bool isFull;

  _AeroTrashPainter({required this.isFull});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.88), width: w * 0.58, height: h * 0.14),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Crumpled white papers sticking out when full
    if (isFull) {
      final p1 = Path()
        ..moveTo(w * 0.28, h * 0.32)
        ..lineTo(w * 0.42, h * 0.15)
        ..lineTo(w * 0.56, h * 0.26)
        ..lineTo(w * 0.44, h * 0.36)
        ..close();
      final p2 = Path()
        ..moveTo(w * 0.48, h * 0.30)
        ..lineTo(w * 0.64, h * 0.17)
        ..lineTo(w * 0.74, h * 0.30)
        ..lineTo(w * 0.58, h * 0.36)
        ..close();
      canvas.drawPath(p1, Paint()..color = const Color(0xFFF8FAFC));
      canvas.drawPath(p2, Paint()..color = const Color(0xFFE2E8F0));
    }

    // Translucent glass basket body
    final body = Path()
      ..moveTo(w * 0.22, h * 0.28)
      ..lineTo(w * 0.29, h * 0.82)
      ..quadraticBezierTo(w * 0.30, h * 0.88, w * 0.38, h * 0.88)
      ..lineTo(w * 0.62, h * 0.88)
      ..quadraticBezierTo(w * 0.70, h * 0.88, w * 0.71, h * 0.82)
      ..lineTo(w * 0.78, h * 0.28)
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xDDE2E8F0),
            Color(0xBB94A3B8),
            Color(0xDD475569),
            Color(0xCCE2E8F0),
          ],
          stops: [0.0, 0.35, 0.75, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.65),
    );

    // Metallic rim ellipse
    final rimRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.28), width: w * 0.56, height: h * 0.14);
    canvas.drawOval(
      rimRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAFC), Color(0xFF94A3B8)],
        ).createShader(rimRect),
    );
    canvas.drawOval(
      rimRect.deflate(w * 0.05),
      Paint()..color = const Color(0x881E293B),
    );

    // Glass ribs
    final ribPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.38, h * 0.39), Offset(w * 0.40, h * 0.79), ribPaint);
    canvas.drawLine(Offset(w * 0.50, h * 0.39), Offset(w * 0.50, h * 0.80), ribPaint);
    canvas.drawLine(Offset(w * 0.62, h * 0.39), Offset(w * 0.60, h * 0.79), ribPaint);
  }

  @override
  bool shouldRepaint(_AeroTrashPainter old) => old.isFull != isFull;
}

/// Live Win32 Battery Docklet.
class BatteryDockletIcon extends StatelessWidget {
  final BatteryInfo info;
  final double size;

  const BatteryDockletIcon({super.key, required this.info, required this.size});

  @override
  Widget build(BuildContext context) {
    final fillColor = !info.hasBattery
        ? const Color(0xFF38BDF8)
        : info.percent <= 20
            ? const Color(0xFFEF4444)
            : info.percent <= 45
                ? const Color(0xFFF59E0B)
                : const Color(0xFF22C55E);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF334155), Color(0xFF0F172A)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white70, width: 1.3),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (info.percent / 100).clamp(0.06, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 2.5,
                  height: size * 0.16,
                  margin: const EdgeInsets.only(left: 1.5),
                  decoration: const BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.acOnline || info.charging)
                  const Icon(Icons.bolt_rounded, size: 10, color: Color(0xFFFDE047)),
                Text(
                  info.hasBattery ? '${info.percent}%' : 'AC',
                  style: TextStyle(
                    fontSize: (size * 0.20).clamp(8.5, 13),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live Win32 SysStats Docklet (CPU / RAM).
class SysStatsDockletIcon extends StatelessWidget {
  final SysStatsInfo stats;
  final double size;

  const SysStatsDockletIcon({super.key, required this.stats, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF020617)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      padding: EdgeInsets.all(size * 0.13),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bar('CPU', stats.cpuPercent, const Color(0xFF38BDF8), size),
          _bar('RAM', stats.ramPercent, const Color(0xFF34D399), size),
        ],
      ),
    );
  }

  Widget _bar(String label, int pct, Color color, double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: (s * 0.15).clamp(7.5, 10.5),
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: (s * 0.15).clamp(7.5, 10.5),
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: (s * 0.08).clamp(3, 5.5),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Crisp Calendar Docklet icon.
class CalendarDockletIcon extends StatelessWidget {
  final DateTime now;
  final double size;

  const CalendarDockletIcon({super.key, required this.now, required this.size});

  static const _months = [
    'ЯНВ', 'ФЕВ', 'МАР', 'АПР', 'МАЙ', 'ИЮН',
    'ИЮЛ', 'АВГ', 'СЕН', 'ОКТ', 'НОЯ', 'ДЕК',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        color: const Color(0xFFF8FAFC),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFBE123C)]),
            ),
            alignment: Alignment.center,
            child: Text(
              _months[now.month - 1],
              style: TextStyle(
                fontSize: (size * 0.17).clamp(7.5, 11.5),
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${now.day}',
                style: TextStyle(
                  fontSize: (size * 0.44).clamp(15, 34),
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean RocketDock Aero glossy icon tile (Calculator, Terminal, Settings, Power, Folders, etc.).
class DockGlyphTile extends StatelessWidget {
  final String iconKey;
  final Color color;
  final double size;

  const DockGlyphTile({
    super.key,
    required this.iconKey,
    required this.color,
    required this.size,
  });

  static IconData resolveIconData(String key) {
    switch (key) {
      case 'folder-blue':
      case 'folder-amber':
      case 'folder-emerald':
        return Icons.folder_rounded;
      case 'notes':
        return Icons.description_rounded;
      case 'calculator':
        return Icons.calculate_rounded;
      case 'clock':
        return Icons.schedule_rounded;
      case 'settings':
        return Icons.settings_rounded;
      case 'trash':
        return Icons.delete_rounded;
      case 'code':
        return Icons.code_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'globe':
        return Icons.public_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'video':
        return Icons.play_arrow_rounded;
      case 'mail':
        return Icons.mail_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'palette':
        return Icons.palette_rounded;
      case 'camera':
        return Icons.camera_alt_rounded;
      case 'cloud':
        return Icons.cloud_rounded;
      case 'book':
        return Icons.menu_book_rounded;
      case 'gamepad':
        return Icons.sports_esports_rounded;
      case 'briefcase':
        return Icons.work_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'power':
        return Icons.power_settings_new_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      case 'rocket':
      default:
        return Icons.rocket_launch_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lighter = Color.lerp(color, Colors.white, 0.18) ?? color;
    final darker = Color.lerp(color, const Color(0xFF020617), 0.42) ?? color;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lighter, color, darker],
          stops: const [0.0, 0.48, 1.0],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 7, offset: Offset(0, 3)),
        ],
      ),
      child: Stack(
        children: [
          // Top subtle Aero glass highlight
          Positioned(
            left: 1,
            right: 1,
            top: 1,
            height: size * 0.44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(size * 0.25),
                  bottom: Radius.elliptical(size * 0.5, size * 0.12),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.36),
                    Colors.white.withValues(alpha: 0.04),
                  ],
                ),
              ),
            ),
          ),
          // Crisp glyph with subtle drop shadow
          Center(
            child: Icon(
              resolveIconData(iconKey),
              color: Colors.white,
              size: size * 0.54,
              shadows: const [
                Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
