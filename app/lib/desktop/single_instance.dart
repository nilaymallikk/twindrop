import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of [SingleInstance.acquire].
class SingleInstanceResult {
  const SingleInstanceResult._(this.instance, {required this.isPrimary});

  final SingleInstance instance;
  final bool isPrimary;

  bool get isSecondary => !isPrimary;
}

/// One running TwinDrop per user session, coordinated over a unix socket.
///
/// The primary listens; a second launch becomes a client, sends its flag, and
/// the host exits. The socket lives at `$XDG_RUNTIME_DIR/twindrop.sock`.
class SingleInstance {
  SingleInstance._primary(ServerSocket server)
    : _server = server,
      _client = null,
      isPrimary = true;

  SingleInstance._secondary(Socket client)
    : _server = null,
      _client = client,
      isPrimary = false;

  static const _allowedCommands = {'--open', '--quick-send', '--quit'};

  final ServerSocket? _server;
  final Socket? _client;
  final StreamController<String> _commands =
      StreamController<String>.broadcast();
  final bool isPrimary;

  /// Commands forwarded by later launches, one per event.
  Stream<String> get commands => _commands.stream;

  static String get socketPath {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final dir = (runtimeDir != null && runtimeDir.isNotEmpty)
        ? runtimeDir
        : Directory.systemTemp.path;
    return '$dir${Platform.pathSeparator}twindrop.sock';
  }

  static Future<SingleInstanceResult> acquire() async {
    final path = socketPath;

    final existing = await _tryConnect(path);
    if (existing != null) {
      return SingleInstanceResult._(
        SingleInstance._secondary(existing),
        isPrimary: false,
      );
    }

    // Nothing answered; remove whatever stale node is left behind.
    try {
      if (await File(path).exists()) await File(path).delete();
    } catch (_) {
      // If it cannot be removed, bind below reports the real problem.
    }

    try {
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      final instance = SingleInstance._primary(server);
      instance._listen();
      await instance._restrictPermissions(path);
      return SingleInstanceResult._(instance, isPrimary: true);
    } on SocketException {
      // Lost a race with another launch: join it instead of failing.
      final winner = await _tryConnect(path);
      if (winner != null) {
        return SingleInstanceResult._(
          SingleInstance._secondary(winner),
          isPrimary: false,
        );
      }
      // No usable socket (permissions, path length, no runtime dir): run
      // without single-instance coordination rather than refusing to start.
      return SingleInstanceResult._(
        SingleInstance._primaryPlaceholder(),
        isPrimary: true,
      );
    }
  }

  SingleInstance._primaryPlaceholder()
    : _server = null,
      _client = null,
      isPrimary = true;

  static Future<Socket?> _tryConnect(String path) async {
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 300),
      );
      return socket;
    } catch (_) {
      return null;
    }
  }

  void _listen() {
    final server = _server;
    if (server == null) return;
    server.listen((client) {
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final command = line.trim();
              if (_allowedCommands.contains(command)) {
                _commands.add(command);
              }
            },
            onError: (_) => client.destroy(),
            onDone: client.destroy,
            cancelOnError: true,
          );
    }, onError: (_) {});
  }

  Future<void> _restrictPermissions(String path) async {
    try {
      await Process.run('chmod', ['600', path]);
    } catch (_) {
      // Filesystem without chmod support; the directory permissions still
      // bound access.
    }
  }

  /// Forward [command] to the primary. Only valid on a secondary instance.
  Future<void> send(String command) async {
    if (!_allowedCommands.contains(command)) {
      throw ArgumentError.value(command, 'command', 'Unknown command');
    }
    final client = _client;
    if (client == null) {
      throw StateError('Only a secondary instance can forward commands');
    }
    client.write('$command\n');
    await client.flush();
  }

  Future<void> dispose() async {
    final client = _client;
    if (client != null) {
      try {
        await client.close();
      } catch (_) {
        // Already gone.
      }
    }
    final server = _server;
    if (server != null) {
      try {
        await server.close();
      } catch (_) {
        // Already gone.
      }
      // Dart removes the node on close on most platforms; clean up when it
      // does not.
      try {
        final file = File(socketPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Not ours to remove, or already gone.
      }
    }
    if (!_commands.isClosed) await _commands.close();
  }
}
