import 'dart:async';

/// Broadcasts "something changed" signals to the UI and to the sync engines.
///
/// The database is the source of truth; this bus only carries revisions. A
/// monotonic [revision] int is emitted after each committed local or merged
/// remote write. UI code can map it to fresh queries (`watchNotes`, `watch`) so
/// there is one simple stream to wire in riverpod.
class ChangeBus {
  ChangeBus();

  final StreamController<int> _controller = StreamController<int>.broadcast();
  int _revision = 0;

  int get revision => _revision;

  /// Stream of increasing revision numbers (broadcast, replay-free).
  Stream<int> get stream => _controller.stream;

  /// Signal a committed change. Safe to call after the transaction commits.
  void notify() {
    _revision++;
    if (!_controller.isClosed) _controller.add(_revision);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
