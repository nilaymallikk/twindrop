import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/change.dart';
import '../models/enums.dart';
import '../util/logger.dart';

/// Read/clear access to the visible quarantine (`SYNC-006`, Settings → Data).
class QuarantineService {
  QuarantineService({required AppDatabase db, required Logger logger})
      : _db = db,
        _logger = logger;

  final AppDatabase _db;
  final Logger _logger;

  Future<List<QuarantineEntry>> list() => _db.quarantined();

  Future<int> count() => _db.quarantineCount();

  Future<void> clear() async {
    await _db.clearQuarantine();
    _logger.info('quarantine cleared');
  }
}
