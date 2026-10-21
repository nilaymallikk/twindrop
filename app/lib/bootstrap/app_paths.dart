import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Filesystem locations for user data. Nothing is ever written inside the
/// AppImage mount or the APK; everything lives under XDG/app-support dirs
/// (`docs/07-linux.md`, `docs/04-data-model.md` §Integrity).
class AppPaths {
  AppPaths({
    required this.supportDir,
    required this.documentsDir,
  });

  /// App-private data: SQLite replica, TLS identity, quarantine exports.
  final Directory supportDir;

  /// User-visible exports (Markdown/JSON). May be unavailable on some devices.
  final Directory? documentsDir;

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    Directory? docs;
    try {
      docs = await getApplicationDocumentsDirectory();
    } on Exception {
      docs = null;
    }
    final paths = AppPaths(supportDir: support, documentsDir: docs);
    await paths.ensureDirs();
    return paths;
  }

  String get databasePath => p.join(supportDir.path, 'twindrop.db');

  /// Certificate (PEM) + private key (PKCS#8 PEM, 0600) live here, never in the
  /// application bundle.
  Directory get tlsDir => Directory(p.join(supportDir.path, 'tls'));
  String get certificatePath => p.join(tlsDir.path, 'cert.pem');
  String get privateKeyPath => p.join(tlsDir.path, 'key.pem');

  Directory get exportDir =>
      Directory(p.join((documentsDir ?? supportDir).path, 'TwinDrop'));

  Directory get backupDir => Directory(p.join(supportDir.path, 'backups'));

  Future<void> ensureDirs() async {
    await supportDir.create(recursive: true);
    await tlsDir.create(recursive: true);
    await backupDir.create(recursive: true);
  }

  Future<void> ensureExportDir() => exportDir.create(recursive: true);
}
