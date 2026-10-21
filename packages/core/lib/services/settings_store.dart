import '../db/database.dart';
import '../models/enums.dart';

/// Stable settings keys (local replica only, never synced; `docs/04`).
///
/// These strings are on-disk data: never rename an existing key without a
/// migration.
abstract final class SettingsKeys {
  static const deviceId = 'device.id';
  static const deviceName = 'device.name';
  static const deviceKind = 'device.kind';
  static const protocolVersion = 'protocol.version';
  static const hlcLast = 'hlc.last';
  static const theme = 'ui.theme';
  static const shareDefaultAction = 'share.default_action';
  static const cleanLinks = 'links.clean_instagram';
  static const notificationsEnabled = 'notifications.enabled';
  static const keepAliveConsent = 'android.keep_alive_consent';
  static const paused = 'connection.paused';
  static const serverPort = 'server.port';
  static const lastExportAt = 'export.last_at';
}

/// Typed accessor over the `settings` table. All reads are cheap; writes are
/// single upserts. UI code should re-read after a [ChangeBus] revision.
class SettingsStore {
  SettingsStore(this._db);
  final AppDatabase _db;

  Future<String?> getString(String key) => _db.getSetting(key);

  Future<void> setString(String key, String value) =>
      _db.setSetting(key, value);

  Future<void> remove(String key) => _db.deleteSetting(key);

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final v = await _db.getSetting(key);
    if (v == null) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      _db.setSetting(key, value ? '1' : '0');

  Future<int?> getInt(String key) async {
    final v = await _db.getSetting(key);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setInt(String key, int value) =>
      _db.setSetting(key, value.toString());

  // ---- typed app settings ----

  Future<AppThemeChoice> theme() async =>
      AppThemeChoice.parse(await _db.getSetting(SettingsKeys.theme) ?? 'dark');

  Future<void> setTheme(AppThemeChoice choice) =>
      _db.setSetting(SettingsKeys.theme, choice.wire);

  Future<ShareDefaultAction> shareDefaultAction() async =>
      ShareDefaultAction.parse(
        await _db.getSetting(SettingsKeys.shareDefaultAction) ?? '',
      );

  Future<void> setShareDefaultAction(ShareDefaultAction action) =>
      _db.setSetting(SettingsKeys.shareDefaultAction, action.wire);

  Future<bool> cleanLinks() => getBool(SettingsKeys.cleanLinks, fallback: true);

  Future<void> setCleanLinks(bool value) =>
      setBool(SettingsKeys.cleanLinks, value);

  Future<bool> notificationsEnabled() =>
      getBool(SettingsKeys.notificationsEnabled, fallback: true);

  Future<void> setNotificationsEnabled(bool value) =>
      setBool(SettingsKeys.notificationsEnabled, value);

  Future<bool> keepAliveConsent() =>
      getBool(SettingsKeys.keepAliveConsent, fallback: true);

  Future<void> setKeepAliveConsent(bool value) =>
      setBool(SettingsKeys.keepAliveConsent, value);

  Future<bool> paused() => getBool(SettingsKeys.paused);

  Future<void> setPaused(bool value) => setBool(SettingsKeys.paused, value);
}
