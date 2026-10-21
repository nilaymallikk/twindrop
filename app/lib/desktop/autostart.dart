import 'dart:io';

import 'package:path/path.dart' as p;

/// Manages `~/.config/autostart/twindrop.desktop`.
class Autostart {
  /// A notice for the UI when the saved autostart entry cannot be repaired.
  String? staleNotice;

  String get desktopFilePath {
    final configHome = Platform.environment['XDG_CONFIG_HOME'];
    final base = (configHome != null && configHome.isNotEmpty)
        ? configHome
        : p.join(Platform.environment['HOME'] ?? '', '.config');
    return p.join(base, 'autostart', 'twindrop.desktop');
  }

  Future<bool> isEnabled() async {
    staleNotice = null;
    final file = File(desktopFilePath);
    if (!await file.exists()) return false;

    String contents;
    try {
      contents = await file.readAsString();
    } catch (_) {
      staleNotice = 'Cannot read the autostart entry at $desktopFilePath.';
      return true;
    }

    final stored = _execPath(contents);
    if (stored == null) {
      staleNotice =
          'The autostart entry has no Exec line. Turn autostart off and on '
          'again to repair it.';
      return true;
    }

    final targetExists =
        await File(stored).exists() || await Directory(stored).exists();
    if (!targetExists) {
      staleNotice =
          'Autostart points to a missing file ($stored). Turn autostart off '
          'and on again.';
      return true;
    }

    // An AppImage can move between launches; keep the entry pointing at the
    // image that is running now instead of collecting stale paths.
    final appImage = Platform.environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty && appImage != stored) {
      await _write(_withHidden(appImage));
    }
    return true;
  }

  Future<void> setEnabled(bool enabled, {required String command}) async {
    staleNotice = null;
    final file = File(desktopFilePath);
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return;
    }

    await file.parent.create(recursive: true);
    await _write(_withHidden(command));
  }

  Future<void> _write(String exec) async {
    final contents = [
      '[Desktop Entry]',
      'Type=Application',
      'Name=TwinDrop',
      'Exec=$exec',
      'Icon=twindrop',
      'X-GNOME-Autostart-enabled=true',
      '',
    ].join('\n');
    await File(desktopFilePath).writeAsString(contents, flush: true);
  }

  String _withHidden(String command) {
    final hasHidden = command
        .split(RegExp(r'\s+'))
        .any((part) => part == '--hidden');
    return hasHidden ? command : '$command --hidden';
  }

  /// First token of the Exec line, with desktop-entry quoting removed.
  String? _execPath(String contents) {
    for (final line in contents.split('\n')) {
      if (!line.startsWith('Exec=')) continue;
      final value = line.substring('Exec='.length).trim();
      if (value.isEmpty) return null;
      if (value.startsWith('"')) {
        final end = value.indexOf('"', 1);
        if (end <= 1) return null;
        return value.substring(1, end);
      }
      return value.split(RegExp(r'\s+')).first;
    }
    return null;
  }
}
