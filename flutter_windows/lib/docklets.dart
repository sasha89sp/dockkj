import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ini_storage.dart';
import 'win32_bridge.dart';

/// Live Analog Clock Docklet painted at 60fps with zero allocations.
class ClockDockletIcon extends StatelessWidget {
  final DateTime now;
  final double size;

  const ClockDockletIcon({super.key, required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ClockFacePainter(now)),
    );
  }
}

class _ClockFacePainter extends CustomPainter {
  final DateTime now;

  _ClockFacePainter(this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;

    // Bezel
    final bezelRect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final bezelPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF334155), Color(0xFF0F172A)],
      ).createShader(bezelRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bezelRect, Radius.circular(size.width * 0.24)),
      bezelPaint,
    );

    // Dial
    canvas.drawCircle(center, radius * 0.85, Paint()..color = const Color(0xFFF8FAFC));

    // Hour ticks
    for (var i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;
      final outer = Offset(
        center.dx + math.cos(angle) * radius * 0.76,
        center.dy + math.sin(angle) * radius * 0.76,
      );
      final inner = Offset(
        center.dx + math.cos(angle) * radius * (i % 3 == 0 ? 0.58 : 0.66),
        center.dy + math.sin(angle) * radius * (i % 3 == 0 ? 0.58 : 0.66),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = i % 3 == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B)
          ..strokeWidth = i % 3 == 0 ? 1.8 : 1.0
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
          center.dx + math.cos(rad) * radius * len,
          center.dy + math.sin(rad) * radius * len,
        ),
        Paint()
          ..color = color
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    drawHand(hr * 30, 0.45, 2.4, const Color(0xFF0F172A));
    drawHand(min * 6, 0.66, 1.8, const Color(0xFF1E293B));
    drawHand(sec * 6, 0.72, 1.1, const Color(0xFFE11D48));
    canvas.drawCircle(center, 2.2, Paint()..color = const Color(0xFFE11D48));
  }

  @override
  bool shouldRepaint(_ClockFacePainter old) => old.now.second != now.second;
}

/// Live Win32 Battery Docklet showing real charge % and AC status.
class BatteryDockletIcon extends StatelessWidget {
  final BatteryInfo info;
  final double size;

  const BatteryDockletIcon({super.key, required this.info, required this.size});

  @override
  Widget build(BuildContext context) {
    final fillColor = !info.hasBattery
        ? const Color(0xFF0EA5E9)
        : info.percent <= 20
            ? const Color(0xFFEF4444)
            : info.percent <= 45
                ? const Color(0xFFF59E0B)
                : const Color(0xFF10B981);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF020617)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Battery body
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white70, width: 1.4),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (info.percent / 100).clamp(0.05, 1.0),
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
                  width: 3,
                  height: size * 0.18,
                  margin: const EdgeInsets.only(left: 1.5),
                  decoration: const BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.acOnline || info.charging)
                  const Icon(Icons.bolt_rounded, size: 11, color: Color(0xFFFDE047)),
                Text(
                  info.hasBattery ? '${info.percent}%' : 'AC',
                  style: TextStyle(
                    fontSize: (size * 0.21).clamp(9, 14),
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

/// Live Win32 SysStats Docklet (real CPU % and RAM % bars).
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: EdgeInsets.all(size * 0.13),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _gaugeRow('CPU', stats.cpuPercent, const Color(0xFF38BDF8), size),
          _gaugeRow('RAM', stats.ramPercent, const Color(0xFF34D399), size),
        ],
      ),
    );
  }

  Widget _gaugeRow(String label, int pct, Color color, double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: (s * 0.16).clamp(7.5, 11),
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: (s * 0.16).clamp(7.5, 11),
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
            minHeight: (s * 0.08).clamp(3, 6),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Live Calendar Docklet icon showing today's month and day.
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            color: const Color(0xFFE11D48),
            alignment: Alignment.center,
            child: Text(
              _months[now.month - 1],
              style: TextStyle(
                fontSize: (size * 0.18).clamp(8, 12),
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${now.day}',
                style: TextStyle(
                  fontSize: (size * 0.44).clamp(16, 36),
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

/// Live 2-state Recycle Bin icon (Empty vs Full with Windows item badge).
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

    Widget base;
    if (customPath != null && File(customPath).existsSync()) {
      base = Image.file(
        File(customPath),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: quality,
      );
    } else {
      base = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isFull
                ? const [Color(0xFF64748B), Color(0xFF1E293B)]
                : const [Color(0xFF475569), Color(0xFF0F172A)],
          ),
          border: Border.all(
            color: isFull
                ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.28),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Icon(
          isFull ? Icons.delete_rounded : Icons.delete_outline_rounded,
          color: isFull ? const Color(0xFFF8FAFC) : const Color(0xFFCBD5E1),
          size: size * 0.54,
        ),
      );
    }

    if (!isFull) return base;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              info.itemCount > 99 ? '99+' : '${info.itemCount}',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Live Aero Thumbnail Preview card shown when hovering a minimized window in the dock.
class MinimizedWindowPreviewCard extends StatelessWidget {
  final String title;
  final Uint8List? thumbnailPng;

  const MinimizedWindowPreviewCard({
    super.key,
    required this.title,
    required this.thumbnailPng,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xEA0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(color: Color(0xA6000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumbnailPng != null
                ? Image.memory(
                    thumbnailPng!,
                    width: 208,
                    height: 122,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                : Container(
                    width: 208,
                    height: 100,
                    color: const Color(0xFF1E293B),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.web_asset_rounded,
                      color: Colors.white38,
                      size: 36,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Generic fallback vector icon for built-in or blank dock shortcuts.
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
    final darker = Color.lerp(color, const Color(0xFF020617), 0.36) ?? color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, darker],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: size * 0.46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(size * 0.23)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.32),
                    Colors.white.withValues(alpha: 0.03),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              resolveIconData(iconKey),
              color: Colors.white,
              size: size * 0.54,
            ),
          ),
        ],
      ),
    );
  }
}
