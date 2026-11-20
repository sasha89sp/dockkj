import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class FolderEntryInfo {
  final String name;
  final String fullPath;
  final bool isDirectory;

  const FolderEntryInfo({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
  });
}

class WindowsServices {
  /// Expands Windows environment variables like %USERPROFILE%, %APPDATA%, %LOCALAPPDATA%.
  static String expandEnv(String raw) {
    return raw.replaceAllMapped(
      RegExp(r'%([^%]+)%'),
      (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
    );
  }

  /// Extracts the lowercase .exe filename for matching against Windows tasklist.
  static String? extractProcessExeName(String target) {
    final expanded = expandEnv(target).trim();
    if (expanded.isEmpty ||
        expanded.startsWith('http://') ||
        expanded.startsWith('https://') ||
        expanded.startsWith('ms-')) {
      return null;
    }
    final base = p.basename(expanded).toLowerCase();
    if (base.endsWith('.exe')) return base;
    return null;
  }

  /// Queries running Windows processes via tasklist (lightweight, zero external deps).
  static Future<Set<String>> queryRunningProcesses() async {
    try {
      final res = await Process.run(
        'tasklist',
        ['/FO', 'CSV', '/NH'],
        runInShell: false,
      );
      if (res.exitCode != 0) return const {};
      final lines = res.stdout.toString().split(RegExp(r'\r?\n'));
      final names = <String>{};
      for (final line in lines) {
        if (line.isEmpty) continue;
        final firstQuoteEnd = line.indexOf('"', 1);
        if (line.startsWith('"') && firstQuoteEnd > 1) {
          names.add(line.substring(1, firstQuoteEnd).toLowerCase());
        }
      }
      return names;
    } catch (_) {
      return const {};
    }
  }

  /// Extracts a real native Windows icon from .exe / .lnk into portable icons/<id>.png.
  static Future<String?> extractNativeIconPng({
    required String target,
    required Directory iconsDir,
    required String itemId,
  }) async {
    final expanded = expandEnv(target).trim();
    if (expanded.isEmpty ||
        expanded.startsWith('http://') ||
        expanded.startsWith('https://') ||
        expanded.startsWith('ms-')) {
      return null;
    }

    final safeId = itemId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = '$safeId.png';
    final outPath = p.join(iconsDir.path, fileName);

    final escTarget = expanded.replaceAll("'", "''");
    final escOut = outPath.replaceAll("'", "''");

    final ps = '''
Add-Type -AssemblyName System.Drawing
\$t = '$escTarget'
if (\$t.ToLower().EndsWith('.lnk') -and (Test-Path \$t)) {
  \$sh = New-Object -ComObject WScript.Shell
  \$sc = \$sh.CreateShortcut(\$t)
  if (\$sc.TargetPath) { \$t = \$sc.TargetPath }
}
if (-not (Test-Path \$t -PathType Leaf)) {
  \$cmd = Get-Command \$t -ErrorAction SilentlyContinue
  if (\$cmd -and \$cmd.Source) { \$t = \$cmd.Source }
}
if (Test-Path \$t -PathType Leaf) {
  \$ico = [System.Drawing.Icon]::ExtractAssociatedIcon(\$t)
  if (\$ico) {
    \$bmp = \$ico.ToBitmap()
    \$bmp.Save('$escOut', [System.Drawing.Imaging.ImageFormat]::Png)
    \$bmp.Dispose()
    \$ico.Dispose()
  }
}
''';

    try {
      await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', ps],
        runInShell: false,
      );
      if (await File(outPath).exists()) {
        return fileName;
      }
    } catch (_) {}
    return null;
  }

  /// Launches a URL, folder, .exe, or protocol URI cleanly.
  static Future<void> launchTarget({
    required String type,
    required String target,
    String args = '',
  }) async {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return;

    if (type == 'url' || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final resolved = expandEnv(trimmed);
    final argList = args.trim().isEmpty ? <String>[] : args.trim().split(RegExp(r'\s+'));

    try {
      if (Directory(resolved).existsSync()) {
        await Process.start('explorer.exe', [resolved], mode: ProcessStartMode.detached);
        return;
      }
      if (resolved.contains(':') && !resolved.contains('\\')) {
        // Windows protocol URI (e.g. ms-settings:, ms-clock:)
        await Process.start('cmd', ['/c', 'start', '', resolved], runInShell: true, mode: ProcessStartMode.detached);
        return;
      }
      await Process.start(
        resolved,
        argList,
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      await Process.start(
        'cmd',
        ['/c', 'start', '', resolved, ...argList],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    }
  }

  /// Lists real files & subfolders inside a Windows directory for Live Folder Stacks.
  static List<FolderEntryInfo> listDirectoryEntries(String rawDirPath, {int limit = 24}) {
    final resolved = expandEnv(rawDirPath).trim();
    if (resolved.isEmpty) return const [];
    final dir = Directory(resolved);
    if (!dir.existsSync()) return const [];
    try {
      final entities = dir.listSync(followLinks: false);
      final dirs = <FolderEntryInfo>[];
      final files = <FolderEntryInfo>[];
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.') || name.toLowerCase() == 'desktop.ini') continue;
        final isDir = e is Directory;
        final info = FolderEntryInfo(name: name, fullPath: e.path, isDirectory: isDir);
        if (isDir) {
          dirs.add(info);
        } else {
          files.add(info);
        }
      }
      dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return [...dirs, ...files].take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  static File _startupLinkFile() {
    final appData = Platform.environment['APPDATA'] ?? '';
    return File(p.join(appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'AeroDock Portable.lnk'));
  }

  static bool isStartupEnabled() {
    try {
      return _startupLinkFile().existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Creates or removes a Windows Startup shortcut in shell:startup (no admin rights required).
  static Future<bool> setStartupEnabled(bool enable) async {
    final lnk = _startupLinkFile();
    try {
      if (!enable) {
        if (await lnk.exists()) await lnk.delete();
        return false;
      }
      final exe = Platform.resolvedExecutable.replaceAll("'", "''");
      final workDir = File(Platform.resolvedExecutable).parent.path.replaceAll("'", "''");
      final lnkPath = lnk.path.replaceAll("'", "''");
      final ps = '''
\$sh = New-Object -ComObject WScript.Shell
\$sc = \$sh.CreateShortcut('$lnkPath')
\$sc.TargetPath = '$exe'
\$sc.WorkingDirectory = '$workDir'
\$sc.Description = 'AeroDock Portable'
\$sc.Save()
''';
      await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', ps],
        runInShell: false,
      );
      return await lnk.exists();
    } catch (_) {
      return false;
    }
  }
}
