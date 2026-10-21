/// Typed failures for every core operation (`docs/03` error boundary).
///
/// Everything that can fail across a boundary (network, TLS, protocol,
/// validation, storage) throws or returns one of these instead of a raw
/// exception, so the UI can show short actionable copy (`docs/02`) and the
/// diagnostics screen can group by category without parsing strings.
///
/// Messages here are **safe for logs and UI**: they carry no message/note
/// content, no URLs, no tokens and no keys.
library;

/// Machine-readable error codes. Also used in HTTP error bodies (`docs/05`)
/// and WS `error` frames.
abstract final class ErrorCodes {
  static const validationError = 'validation_error';
  static const unauthorized = 'unauthorized';
  static const forbidden = 'forbidden';
  static const notFound = 'not_found';
  static const rateLimited = 'rate_limited';
  static const payloadTooLarge = 'payload_too_large';
  static const pairingFailed = 'pairing_failed';
  static const pairingExpired = 'pairing_expired';
  static const serverBusy = 'server_busy';
  static const unsupportedVersion = 'unsupported_version';
  static const certificateMismatch = 'certificate_mismatch';
  static const internalError = 'internal_error';
  static const networkError = 'network_error';
  static const storageError = 'storage_error';
  static const serverShutdown = 'server_shutdown';
}

/// Base class for all TwinDrop failures.
sealed class TwinDropError implements Exception {
  const TwinDropError(this.message, {this.cause});

  /// Stable machine code (`ErrorCodes`).
  String get code;

  /// Short, non-sensitive human message; safe for logs and UI.
  final String message;

  /// Optional underlying error. Only its runtime type may be logged.
  final Object? cause;

  /// Whether retrying the same operation could succeed.
  bool get retryable => false;

  /// Default HTTP status for REST responses.
  int get httpStatus => 400;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Local or remote payload failed validation (`docs/04` §Validation).
final class ValidationError extends TwinDropError {
  const ValidationError(super.message, {super.cause});

  @override
  String get code => ErrorCodes.validationError;
}

/// Payload exceeds a documented size limit; rejected, never truncated.
final class PayloadTooLargeError extends TwinDropError {
  const PayloadTooLargeError(super.message, {super.cause});

  @override
  String get code => ErrorCodes.payloadTooLarge;

  @override
  int get httpStatus => 413;
}

/// Missing or invalid bearer token.
final class UnauthorizedError extends TwinDropError {
  const UnauthorizedError([super.message = 'authentication required']);

  @override
  String get code => ErrorCodes.unauthorized;

  @override
  int get httpStatus => 401;
}

/// Valid token for a revoked device, or a forbidden action.
final class ForbiddenError extends TwinDropError {
  const ForbiddenError([super.message = 'not allowed']);

  @override
  String get code => ErrorCodes.forbidden;

  @override
  int get httpStatus => 403;
}

/// Entity does not exist (or is not visible).
final class NotFoundError extends TwinDropError {
  const NotFoundError([super.message = 'not found']);

  @override
  String get code => ErrorCodes.notFound;

  @override
  int get httpStatus => 404;
}

/// Pairing/invalid-action rate limit or lockout (`PAIR-010`).
final class RateLimitedError extends TwinDropError {
  const RateLimitedError({this.retryAfterSeconds = 60})
      : super('too many attempts');

  final int retryAfterSeconds;

  @override
  String get code => ErrorCodes.rateLimited;

  @override
  bool get retryable => true;

  @override
  int get httpStatus => 429;

}

/// Pairing failed. Deliberately generic so failures are not distinguishable
/// (`docs/05` §Abuse controls).
final class PairingFailedError extends TwinDropError {
  const PairingFailedError({this.expired = false, super.cause})
      : super('pairing failed');

  final bool expired;

  @override
  String get code => expired ? ErrorCodes.pairingExpired : ErrorCodes.pairingFailed;

  @override
  int get httpStatus => 400;
}

/// The remote certificate does not match the pinned SHA-256 fingerprint.
/// Never auto-accepted: the user must re-pair deliberately (`docs/08`).
final class CertificateMismatchError extends TwinDropError {
  const CertificateMismatchError({super.cause})
      : super('the desktop certificate does not match the saved pin; re-pair '
            'to continue');

  @override
  String get code => ErrorCodes.certificateMismatch;

  @override
  int get httpStatus => 400;
}

/// Network/dial/WS failure. Retryable in principle; the ConnectionManager
/// applies backoff.
final class NetworkError extends TwinDropError {
  const NetworkError(super.message, {super.cause});

  @override
  String get code => ErrorCodes.networkError;

  @override
  bool get retryable => true;
}

/// Malformed frame/QR/HTTP payload.
final class ProtocolError extends TwinDropError {
  const ProtocolError(super.message, {super.cause});

  @override
  String get code => ErrorCodes.validationError;
}

/// Unknown protocol/schema/entity version: stop sync, do not skip and advance
/// (`SYNC-007`).
final class UnsupportedVersionError extends TwinDropError {
  const UnsupportedVersionError(super.message);

  @override
  String get code => ErrorCodes.unsupportedVersion;

  @override
  int get httpStatus => 426;
}

/// SQLite/storage failure. If the database is corrupt the caller must back it
/// up before recovery (`docs/04`).
final class StorageError extends TwinDropError {
  const StorageError(super.message, {super.cause});

  @override
  String get code => ErrorCodes.storageError;

  @override
  int get httpStatus => 500;
}

/// Unexpected internal failure. Details stay in logs (redacted).
final class InternalError extends TwinDropError {
  const InternalError(super.message, {super.cause});

  @override
  String get code => ErrorCodes.internalError;

  @override
  int get httpStatus => 500;
}

/// Server is shutting down (`4000 server_shutdown`).
final class ServerShutdownError extends TwinDropError {
  const ServerShutdownError() : super('server is shutting down');

  @override
  String get code => ErrorCodes.serverShutdown;

  @override
  bool get retryable => true;
}
