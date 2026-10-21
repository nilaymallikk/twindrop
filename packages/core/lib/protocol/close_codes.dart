/// WebSocket close codes used by TwinDrop (`docs/05` §Close codes).
abstract final class CloseCodes {
  static const int serverShutdown = 4000;
  static const int unauthorized = 4401;
  static const int forbidden = 4403;
  static const int duplicateSession = 4409;
  static const int upgradeRequired = 4426;
  static const int rateLimited = 4429;
  static const int internal = 4500;

  /// Human-readable reason strings (never contain secrets/content).
  static const String reasonUnauthorized = 'unauthorized';
  static const String reasonRevoked = 'revoked';
  static const String reasonDuplicate = 'duplicate_session';
  static const String reasonUpgrade = 'upgrade_required';
  static const String reasonRateLimited = 'rate_limited';
  static const String reasonShutdown = 'server_shutdown';
  static const String reasonInternal = 'internal_error';
}
