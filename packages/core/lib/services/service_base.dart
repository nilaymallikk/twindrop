import '../db/database.dart';
import '../db/store_ops.dart';
import '../util/hlc.dart';
import '../util/logger.dart';
import '../sync/change_bus.dart';

/// Shared plumbing for the local-first services.
///
/// Every service writes through [AppDatabase] inside a transaction, appends a
/// change-log row in the same transaction and only then calls [notifyChanged]
/// (`docs/04` §Write path: nothing leaves the device before the commit).
abstract class CoreService {
  CoreService({
    required this.db,
    required this.clock,
    required this.bus,
    required this.logger,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final HlcClock clock;
  final ChangeBus bus;
  final Logger logger;
  final int Function() _nowMs;

  int nowMs() => _nowMs();

  /// Next HLC for a local write, persisted immediately (same transaction when
  /// called inside one, because drift resolves the zone executor).
  Future<String> stamp() async {
    final value = clock.next().value;
    await db.saveHlcValue(value);
    return value;
  }

  void notifyChanged() => bus.notify();
}
