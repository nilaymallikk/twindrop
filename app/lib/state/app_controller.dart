import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:twindrop_core/core.dart';

import '../bootstrap/app_paths.dart';
import '../features/models.dart';
import '../platform/android/android_platform.dart';

/// Desktop integrations are injected by `main.dart` so this file stays free of
/// Linux-only imports (Android builds must not depend on window_manager).
class DesktopHooks {
  const DesktopHooks({
    this.onStatus,
    this.onPaused,
    this.isAutostartEnabled,
    this.setAutostart,
    this.isTrayAvailable,
    this.quickSendCommand,
    this.onHideOnBlurChanged,
    this.onShowMain,
    this.onShowPopup,
    this.onHideWindow,
  });

  final void Function({required String label, required bool connected, required int unread})?
      onStatus;
  final void Function(bool paused)? onPaused;
  final Future<bool> Function()? isAutostartEnabled;
  final Future<void> Function(bool enabled)? setAutostart;
  final bool Function()? isTrayAvailable;
  final String? quickSendCommand;
  final Future<void> Function(bool hide)? onHideOnBlurChanged;
  final VoidCallback? onShowMain;
  final VoidCallback? onShowPopup;
  final VoidCallback? onHideWindow;
}

/// Single application controller: owns the core runtime and all UI-visible
/// state. Screens stay pure; the host (this controller) performs every action.
class AppController extends ChangeNotifier {
  AppController({
    required this.paths,
    required this.platform,
    this.desktopHooks = const DesktopHooks(),
    CoreNotifier? notifier,
    TokenStore? tokenStore,
    Logger? logger,
  })  : _notifier = notifier,
        _tokenStore = tokenStore,
        _logger = logger ?? Logger.silent;

  final AppPaths paths;
  final CorePlatform platform;
  final DesktopHooks desktopHooks;
  final CoreNotifier? _notifier;
  final TokenStore? _tokenStore;
  final Logger _logger;

  CoreRuntime? runtime;
  DiagnosticsSnapshot? diagnostics;

  bool initialized = false;
  bool busy = false;
  String? fatalError;
  String? toast;

  AppSection section = AppSection.chat;
  AppThemeChoice themeChoice = AppThemeChoice.dark;
  String deviceName = 'TwinDrop';
  String appVersion = '0.1.0';
  ConnectionStatus status = ConnectionStatus.unpaired;
  List<Peer> peers = const <Peer>[];
  String? lastError;

  List<ChatEntry> messages = const <ChatEntry>[];
  bool loadingChat = false;
  String? chatError;
  bool hasMoreMessages = false;

  List<Category> categories = const <Category>[];
  List<Item> notes = const <Item>[];
  bool loadingNotes = false;
  String? notesError;
  String selectedCategoryId = Category.inboxId;
  String searchQuery = '';
  Map<String, int> categoryCounts = const <String, int>{};
  NotepadUndo? noteUndo;

  bool notifications = true;
  bool cleanLinks = true;
  bool paused = false;
  ShareDefaultAction shareAction = ShareDefaultAction.notepad;
  bool keepAliveEnabled = false;
  bool keepAliveSupported = false;
  bool notificationsSupported = true;
  bool batteryOptimized = true;
  bool autostart = false;
  bool autostartSupported = false;
  bool hideOnBlur = true;
  bool trayAvailable = true;
  String quickSendCommand = '';

  DesktopPairingData desktopPairing = const DesktopPairingData(
    stage: DesktopPairingStage.idle,
  );
  PhoneOnboardingData phoneOnboarding = const PhoneOnboardingData(
    stage: PhoneOnboardingStage.welcome,
  );
  PairingSession? _pairingSession;
  ManualProbe? _manualProbe;
  String? _pendingManualHostPort;
  Timer? _pairingTimer;
  Timer? _searchDebounce;
  Timer? _refreshDebounce;

  StreamSubscription<int>? _revisionSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<List<Peer>>? _peersSub;
  StreamSubscription<PairingRequestInfo>? _pairingReqSub;

  int _lastReadAt = 0;
  bool _foreground = true;
  bool popupMode = false;
  String? _pendingManualCode;

  bool get isDesktop => platform == CorePlatform.desktop;
  bool get isPhone => platform == CorePlatform.phone;
  bool get isPaired => peers.any((p) => !p.isRevoked);
  Peer? get activePeer {
    final active = peers.where((p) => !p.isRevoked).toList();
    return active.isEmpty ? null : active.first;
  }

  int get unreadChat =>
      messages.where((m) => !m.mine && m.createdAt > _lastReadAt).length;

  Future<void> init({bool startConnection = true}) async {
    try {
      busy = true;
      notifyListeners();
      final store = _tokenStore ??
          (platform == CorePlatform.phone
              ? SecureTokenStore()
              : MemoryTokenStore());
      final notifier = _notifier ??
          (platform == CorePlatform.phone
              ? AndroidNotifier()
              : const _NoopNotifier());
      final multicast = platform == CorePlatform.phone
          ? AndroidMulticastLock()
          : NoopMulticastLock();

      final name = await _resolveDeviceName();
      final version = await _resolveVersion();
      final rt = await CoreRuntime.open(
        platform: platform,
        deviceName: name,
        dataDir: paths.supportDir.path,
        tokenStore: store,
        multicastLock: multicast,
        notifier: notifier,
        appVersion: version,
        logger: _logger,
      );
      runtime = rt;
      deviceName = name;
      appVersion = version;
      themeChoice = await rt.settings.theme();
      notifications = await rt.settings.notificationsEnabled();
      cleanLinks = await rt.settings.cleanLinks();
      shareAction = await rt.settings.shareDefaultAction();
      paused = await rt.settings.paused();
      hideOnBlur =
          await rt.settings.getBool('desktop.hide_on_blur', fallback: true);
      _lastReadAt = await _readLastReadAt();

      _revisionSub = rt.revisionStream.listen((_) => _scheduleRefresh());
      _statusSub = rt.statusStream.listen((next) {
        status = next;
        _publishStatus();
        notifyListeners();
      });
      _peersSub = rt.peersStream.listen((next) {
        peers = next;
        _publishStatus();
        notifyListeners();
      });
      status = rt.status;
      await rt.start();
      peers = await rt.peers.list();

      if (platform == CorePlatform.phone) {
        keepAliveSupported = true;
        notificationsSupported = await AndroidPlatform.areNotificationsEnabled();
        keepAliveEnabled = await AndroidPlatform.isKeepAliveRunning();
        batteryOptimized = !(await AndroidPlatform.isIgnoringBattery());
        await _syncKeepAlive();
        await _importPendingShares();
      }
      if (platform == CorePlatform.desktop) {
        autostartSupported = desktopHooks.isAutostartEnabled != null;
        if (autostartSupported) {
          autostart = await desktopHooks.isAutostartEnabled!.call();
        }
        trayAvailable = desktopHooks.isTrayAvailable?.call() ?? true;
        quickSendCommand = desktopHooks.quickSendCommand ?? '';
      }
      await refresh();
      if (startConnection && platform == CorePlatform.phone) rt.retryNow();
      initialized = true;
      busy = false;
      notifyListeners();
    } on Object catch (e) {
      fatalError = _messageFor(e);
      initialized = true;
      busy = false;
      notifyListeners();
    }
  }

  Future<String> _resolveDeviceName() async {
    if (platform == CorePlatform.phone) {
      try {
        final info = await AndroidPlatform.platformInfo();
        final model = info['model'] as String?;
        if (model != null && model.trim().isNotEmpty) return model.trim();
      } on Object {
        // fall through
      }
      return 'Phone';
    }
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } on Object {
      // ignore
    }
    return 'Desktop';
  }

  Future<String> _resolveVersion() async {
    if (platform == CorePlatform.phone) {
      try {
        final info = await AndroidPlatform.version();
        return info['versionName'] as String? ?? '0.1.0';
      } on Object {
        return '0.1.0';
      }
    }
    return '0.1.0';
  }

  Future<int> _readLastReadAt() async =>
      await runtime!.settings.getInt('ui.last_read_at') ?? 0;

  Future<void> _writeLastReadAt(int at) async {
    _lastReadAt = at;
    await runtime!.settings.setInt('ui.last_read_at', at);
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) runtime?.retryNow();
  }

  bool get isForeground => _foreground;

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), refresh);
  }

  Future<void> refresh() async {
    final rt = runtime;
    if (rt == null) return;
    await Future.wait<void>([_loadMessages(), _loadNotepad(), _loadPeers()]);
    diagnostics = await rt.diagnostics();
    notifyListeners();
  }

  Future<void> _loadPeers() async {
    peers = await runtime!.peers.list();
  }

  Future<void> _loadMessages() async {
    loadingChat = true;
    try {
      final items = await runtime!.chat.listMessages(limit: 300);
      final deliveries = await Future.wait(
        items.map((item) => runtime!.chat.deliveryFor(item.id)),
      );
      final entries = <ChatEntry>[];
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final mine = item.originDevice == runtime!.deviceId;
        var state = DeliveryState.queued;
        for (final d in deliveries[i]) {
          if (d.state == DeliveryState.delivered) {
            state = DeliveryState.delivered;
          } else if (d.state == DeliveryState.sent &&
              state != DeliveryState.delivered) {
            state = DeliveryState.sent;
          }
        }
        entries.add(ChatEntry(
          item: item,
          mine: mine,
          delivery: state,
          deviceLabel: mine ? 'This phone' : item.originName,
        ));
      }
      messages = entries.reversed.toList(growable: false);
      chatError = null;
    } on Object catch (e) {
      chatError = _messageFor(e);
    } finally {
      loadingChat = false;
    }
  }

  Future<void> _loadNotepad() async {
    loadingNotes = true;
    try {
      categories = await runtime!.notepad.listCategories();
      final all = await runtime!.notepad.listNotes(limit: 10000);
      final counts = <String, int>{};
      for (final note in all) {
        final key = note.categoryId ?? Category.inboxId;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      categoryCounts = counts;
      List<Item> filtered;
      if (searchQuery.trim().isNotEmpty) {
        filtered = await runtime!.notepad.search(
          searchQuery,
          categoryId: selectedCategoryId,
          limit: 500,
        );
      } else {
        filtered = all
            .where((n) => (n.categoryId ?? Category.inboxId) == selectedCategoryId)
            .toList(growable: false);
      }
      filtered.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      notes = filtered;
      notesError = null;
    } on Object catch (e) {
      notesError = _messageFor(e);
    } finally {
      loadingNotes = false;
    }
  }

  // --------------------------------------------------------------- actions ---

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      await runtime!.chat.sendMessage(trimmed);
      await _loadMessages();
      notifyListeners();
    } on Object catch (e) {
      toast = _messageFor(e);
      notifyListeners();
    }
  }

  Future<void> deleteMessage(String id) async {
    try {
      await runtime!.chat.deleteMessage(id);
      await _loadMessages();
      notifyListeners();
    } on Object catch (e) {
      toast = _messageFor(e);
      notifyListeners();
    }
  }

  Future<void> saveMessageAsNote(
    String messageId, {
    required SaveToNotepadResult result,
  }) async {
    try {
      await runtime!.chat.saveMessageAsNote(
        messageId,
        categoryId: result.categoryId,
        noteTitle: result.title,
      );
      toast = 'Saved to Notepad.';
    } on Object catch (e) {
      toast = _messageFor(e);
    }
    notifyListeners();
  }

  Future<void> setSection(AppSection next) async {
    section = next;
    if (next == AppSection.chat) {
      await _writeLastReadAt(DateTime.now().millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () async {
      await _loadNotepad();
      notifyListeners();
    });
    notifyListeners();
  }

  void selectCategory(String id) {
    selectedCategoryId = id;
    _loadNotepad().then((_) => notifyListeners());
    notifyListeners();
  }

  Future<void> createNote(NoteDraft draft) async {
    try {
      await runtime!.notepad.createNote(
        text: draft.text,
        title: draft.title.trim().isEmpty ? null : draft.title,
        categoryId: draft.categoryId,
      );
      await _loadNotepad();
      toast = 'Note saved.';
    } on Object catch (e) {
      toast = _messageFor(e);
    }
    notifyListeners();
  }

  Future<void> updateNote(String id, NoteDraft draft) async {
    try {
      final note = await runtime!.notepad.getNote(id);
      if (note == null) throw const NotFoundError('note not found');
      await runtime!.notepad.updateNote(
        id,
        text: draft.text,
        title: draft.title.trim().isEmpty ? null : draft.title,
        clearTitle: draft.title.trim().isEmpty,
      );
      if (note.categoryId != draft.categoryId) {
        await runtime!.notepad.moveNote(id, draft.categoryId);
      }
      await _loadNotepad();
      toast = 'Note saved.';
    } on Object catch (e) {
      toast = _messageFor(e);
    }
    notifyListeners();
  }

  Future<void> togglePinned(Item note) async {
    try {
      await runtime!.notepad.pinNote(note.id, !note.pinned);
      await _loadNotepad();
    } on Object catch (e) {
      toast = _messageFor(e);
    }
    notifyListeners();
  }

  Future<void> deleteNote(Item note) async {
    try {
      await runtime!.notepad.deleteNote(note.id);
      await _loadNotepad();
      noteUndo = NotepadUndo(
        message: 'Note deleted.',
        onUndo: () async {
          try {
            await runtime!.notepad.restoreNote(note.id);
          } on Object catch (e) {
            toast = _messageFor(e);
          }
          noteUndo = null;
          await _loadNotepad();
          notifyListeners();
        },
        onDismissed: () {
          noteUndo = null;
          notifyListeners();
        },
      );
    } on Object catch (e) {
      toast = _messageFor(e);
    }
    notifyListeners();
  }

  CategoryActions get categoryActions => CategoryActions(
        onCreate: (name) async {
          try {
            await runtime!.notepad.createCategory(name);
            await _loadNotepad();
            notifyListeners();
            return null;
          } on Object catch (e) {
            return _messageFor(e);
          }
        },
        onRename: (id, name) async {
          try {
            await runtime!.notepad.renameCategory(id, name);
            await _loadNotepad();
            notifyListeners();
            return null;
          } on Object catch (e) {
            return _messageFor(e);
          }
        },
        onDelete: (id) async {
          try {
            await runtime!.notepad.deleteCategory(id);
            if (selectedCategoryId == id) selectedCategoryId = Category.inboxId;
            await _loadNotepad();
            notifyListeners();
            return true;
          } on Object catch (e) {
            toast = _messageFor(e);
            notifyListeners();
            return false;
          }
        },
        onReorder: (from, to) async {
          final ids = categories.map((c) => c.id).toList();
          if (from < 0 || from >= ids.length || to < 0 || to >= ids.length) {
            return;
          }
          final moved = ids.removeAt(from);
          ids.insert(to, moved);
          try {
            await runtime!.notepad.reorderCategories(ids);
            await _loadNotepad();
            notifyListeners();
          } on Object catch (e) {
            toast = _messageFor(e);
            notifyListeners();
          }
        },
      );

  // ---------------------------------------------------------------- pairing ---

  Future<void> startPairing({bool manual = false}) async {
    final rt = runtime;
    if (rt == null || !isDesktop) return;
    desktopPairing = const DesktopPairingData(
      stage: DesktopPairingStage.waitingForPhone,
      busy: true,
    );
    notifyListeners();
    try {
      final session = await rt.startPairingSession(manual: manual);
      _pairingSession = session;
      await _pairingReqSub?.cancel();
      _pairingReqSub = rt.pairingService!.requests.listen(_onPairingRequest);
      desktopPairing = DesktopPairingData(
        stage: DesktopPairingStage.waitingForPhone,
        qrPayload: manual ? null : session.payload.encode(),
        manualAddress: '${session.payload.hosts.first}:${session.payload.port}',
        fingerprint: rt.identity?.shortFingerprint,
        expiryLabel: _expiryLabel(session),
      );
      _pairingTimer?.cancel();
      _pairingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final s = _pairingSession;
        if (s == null) return;
        if (s.isExpiredAt(DateTime.now())) {
          desktopPairing = const DesktopPairingData(
            stage: DesktopPairingStage.idle,
            errorMessage: 'That code expired. Create a new one.',
          );
          _pairingSession = null;
          _pairingTimer?.cancel();
        } else {
          desktopPairing = _withExpiry(desktopPairing, _expiryLabel(s));
        }
        notifyListeners();
      });
      notifyListeners();
    } on Object catch (e) {
      desktopPairing = DesktopPairingData(
        stage: DesktopPairingStage.error,
        errorMessage: _messageFor(e),
      );
      notifyListeners();
    }
  }

  String _expiryLabel(PairingSession session) {
    final left = session.expiresAt.difference(DateTime.now());
    final seconds = left.inSeconds.clamp(0, 300);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} left';
  }

  DesktopPairingData _withExpiry(DesktopPairingData data, String label) =>
      DesktopPairingData(
        stage: data.stage,
        qrPayload: data.qrPayload,
        manualAddress: data.manualAddress,
        fingerprint: data.fingerprint,
        expiryLabel: label,
        requestId: data.requestId,
        requestDeviceName: data.requestDeviceName,
        requestPlatform: data.requestPlatform,
        confirmationCode: data.confirmationCode,
        connectedDeviceName: data.connectedDeviceName,
        errorMessage: data.errorMessage,
        busy: data.busy,
      );

  void _onPairingRequest(PairingRequestInfo request) {
    if (request.state != PairingState.pendingApproval) return;
    desktopPairing = DesktopPairingData(
      stage: DesktopPairingStage.approval,
      qrPayload: _pairingSession?.payload.encode(),
      manualAddress: desktopPairing.manualAddress,
      fingerprint: desktopPairing.fingerprint,
      expiryLabel: desktopPairing.expiryLabel,
      requestId: request.requestId,
      requestDeviceName: request.displayName,
      requestPlatform: request.platform,
      confirmationCode: request.confirmationCode,
    );
    notifyListeners();
  }

  Future<void> approvePairing(String requestId) async {
    try {
      final peer = await runtime!.approvePairing(requestId);
      desktopPairing = DesktopPairingData(
        stage: DesktopPairingStage.connected,
        connectedDeviceName: peer.name,
      );
      _pairingSession = null;
      _pairingTimer?.cancel();
      peers = await runtime!.peers.list();
      toast = 'Paired with ${peer.name}.';
    } on Object catch (e) {
      desktopPairing = DesktopPairingData(
        stage: DesktopPairingStage.error,
        errorMessage: _messageFor(e),
      );
    }
    notifyListeners();
  }

  Future<void> rejectPairing(String requestId) async {
    await runtime!.rejectPairing(requestId);
    desktopPairing = _withExpiry(
      const DesktopPairingData(stage: DesktopPairingStage.waitingForPhone),
      desktopPairing.expiryLabel ?? '',
    );
    notifyListeners();
  }

  Future<void> cancelPairing() async {
    await runtime?.cancelPairingSession();
    _pairingSession = null;
    _pairingTimer?.cancel();
    desktopPairing = const DesktopPairingData(
      stage: DesktopPairingStage.idle,
    );
    notifyListeners();
  }

  // ------------------------------------------------------------- onboarding ---

  void beginScan() {
    phoneOnboarding = const PhoneOnboardingData(
      stage: PhoneOnboardingStage.scan,
    );
    notifyListeners();
  }

  void beginManual() {
    phoneOnboarding = const PhoneOnboardingData(
      stage: PhoneOnboardingStage.manualEntry,
    );
    notifyListeners();
  }

  Future<void> pairWithQr(String raw) async {
    phoneOnboarding = const PhoneOnboardingData(
      stage: PhoneOnboardingStage.scan,
      busy: true,
    );
    notifyListeners();
    try {
      final result = await runtime!.pairWithQr(
        payload: raw,
        onCode: (code) {
          phoneOnboarding = PhoneOnboardingData(
            stage: PhoneOnboardingStage.confirmCode,
            confirmationCode: code,
            busy: true,
          );
          notifyListeners();
        },
        onWait: (name) {
          phoneOnboarding = PhoneOnboardingData(
            stage: PhoneOnboardingStage.waitingApproval,
            desktopName: name,
          );
          notifyListeners();
        },
      );
      await _afterPaired(result.hostName);
    } on Object catch (e) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.error,
        errorMessage: _messageFor(e),
        errorActionLabel: 'Scan again',
      );
      notifyListeners();
    }
  }

  Future<void> probeManualAddress(String hostPort) async {
    final parsed = _parseHostPort(hostPort);
    if (parsed == null) {
      phoneOnboarding = const PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        errorMessage: 'Enter an address like 192.168.1.23:47321.',
      );
      notifyListeners();
      return;
    }
    _pendingManualHostPort = hostPort;
    phoneOnboarding = const PhoneOnboardingData(
      stage: PhoneOnboardingStage.manualEntry,
      busy: true,
    );
    notifyListeners();
    try {
      final probe = await runtime!.manualProbe(parsed.$1, parsed.$2);
      _manualProbe = probe;
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.fingerprintConfirm,
        manualAddress: hostPort,
        fingerprint: probe.shortFingerprint,
      );
    } on Object catch (e) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        errorMessage: _messageFor(e),
      );
    }
    notifyListeners();
  }

  Future<void> confirmManualFingerprint(String shortFingerprint) async {
    final probe = _manualProbe;
    final code = _pendingManualCode;
    if (probe == null || code == null) return;
    await _completeManualPairing(probe, code);
  }

  /// Manual flow: type address + code, then compare the certificate's short
  /// fingerprint. The pin is stored only after that confirmation.
  Future<void> submitManual(String hostPort, String code) async {
    final parsed = _parseHostPort(hostPort);
    if (parsed == null) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        manualAddress: hostPort,
        errorMessage: 'Enter an address like 192.168.1.23:47321.',
      );
      notifyListeners();
      return;
    }
    if (code.trim().isEmpty) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        manualAddress: hostPort,
        errorMessage: 'Enter the pairing code shown on your desktop.',
      );
      notifyListeners();
      return;
    }
    _pendingManualHostPort = hostPort;
    _pendingManualCode = code.trim();
    phoneOnboarding = PhoneOnboardingData(
      stage: PhoneOnboardingStage.manualEntry,
      manualAddress: hostPort,
      busy: true,
    );
    notifyListeners();
    try {
      final probe = await runtime!.manualProbe(parsed.$1, parsed.$2);
      _manualProbe = probe;
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.fingerprintConfirm,
        manualAddress: hostPort,
        fingerprint: probe.shortFingerprint,
      );
    } on Object catch (e) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        manualAddress: hostPort,
        errorMessage: _messageFor(e),
      );
    }
    notifyListeners();
  }

  Future<void> _completeManualPairing(ManualProbe probe, String code) async {
    phoneOnboarding = const PhoneOnboardingData(
      stage: PhoneOnboardingStage.waitingApproval,
      busy: true,
    );
    notifyListeners();
    try {
      final result = await runtime!.pairManually(
        probe: probe,
        code: code,
        onCode: (c) {
          phoneOnboarding = PhoneOnboardingData(
            stage: PhoneOnboardingStage.confirmCode,
            confirmationCode: c,
            busy: true,
          );
          notifyListeners();
        },
      );
      await _afterPaired(result.hostName);
    } on Object catch (e) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        manualAddress: _pendingManualHostPort,
        fingerprint: probe.shortFingerprint,
        errorMessage: _messageFor(e),
      );
      notifyListeners();
    }
  }

  void setPopupMode(bool value) {
    popupMode = value;
    notifyListeners();
  }

  Future<void> onLifecycleChanged(AppLifecycleState state) async {
    if (!isPhone || runtime == null) return;
    if (state == AppLifecycleState.resumed) {
      setForeground(true);
      await AndroidPlatform.stopKeepAlive();
      await runtime!.startConnection();
      runtime!.retryNow();
      await _importPendingShares();
      await refresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setForeground(false);
      await runtime!.stopConnection();
      await _syncKeepAlive();
    }
  }

  Future<void> pairManually(String code) async {
    final probe = _manualProbe;
    if (probe == null) return;
    phoneOnboarding = const PhoneOnboardingData(
      stage: PhoneOnboardingStage.waitingApproval,
      busy: true,
    );
    notifyListeners();
    try {
      final result = await runtime!.pairManually(
        probe: probe,
        code: code,
        onCode: (c) {
          phoneOnboarding = PhoneOnboardingData(
            stage: PhoneOnboardingStage.confirmCode,
            confirmationCode: c,
            busy: true,
          );
          notifyListeners();
        },
      );
      await _afterPaired(result.hostName);
    } on Object catch (e) {
      phoneOnboarding = PhoneOnboardingData(
        stage: PhoneOnboardingStage.manualEntry,
        manualAddress: _pendingManualHostPort,
        fingerprint: probe.shortFingerprint,
        errorMessage: _messageFor(e),
      );
      notifyListeners();
    }
  }

  Future<void> _afterPaired(String desktopName) async {
    final permissions = <PermissionStepState>[
      const PermissionStepState(permission: PhonePermission.notifications),
      const PermissionStepState(permission: PhonePermission.background),
      const PermissionStepState(permission: PhonePermission.battery),
    ];
    phoneOnboarding = PhoneOnboardingData(
      stage: PhoneOnboardingStage.permissions,
      desktopName: desktopName,
      permissions: permissions,
    );
    peers = await runtime!.peers.list();
    notifyListeners();
  }

  Future<void> decidePermission(
    PhonePermission permission, {
    required bool granted,
    bool skipped = false,
  }) async {
    final current = phoneOnboarding;
    final steps = current.permissions
        .map((s) => s.permission == permission
            ? PermissionStepState(
                permission: permission,
                granted: granted,
                skipped: skipped,
              )
            : s)
        .toList();
    if (permission == PhonePermission.notifications && granted) {
      await AndroidPlatform.requestNotificationPermission();
      notificationsSupported = await AndroidPlatform.areNotificationsEnabled();
    }
    if (permission == PhonePermission.background && granted) {
      keepAliveEnabled = await AndroidPlatform.startKeepAlive(
        desktopName: phoneOnboarding.desktopName,
      );
      if (keepAliveEnabled) {
        await runtime!.settings.setKeepAliveConsent(true);
      }
    }
    if (permission == PhonePermission.battery && granted) {
      await AndroidPlatform.requestIgnoreBatteryOptimizations();
    }
    phoneOnboarding = PhoneOnboardingData(
      stage: current.stage,
      desktopName: current.desktopName,
      confirmationCode: current.confirmationCode,
      manualAddress: current.manualAddress,
      fingerprint: current.fingerprint,
      permissions: steps,
      errorMessage: current.errorMessage,
      errorActionLabel: current.errorActionLabel,
      busy: current.busy,
    );
    notifyListeners();
    if (steps.every((s) => s.decided)) await finishOnboarding();
  }

  Future<void> finishOnboarding() async {
    phoneOnboarding = PhoneOnboardingData(
      stage: PhoneOnboardingStage.connected,
      desktopName: phoneOnboarding.desktopName,
      permissions: phoneOnboarding.permissions,
    );
    await _syncKeepAlive();
    runtime?.retryNow();
    notifyListeners();
  }

  Future<void> _syncKeepAlive() async {
    if (!isPhone) return;
    final consent = await runtime!.settings.keepAliveConsent();
    final active = peers.where((p) => !p.isRevoked).toList();
    if (consent && active.isNotEmpty && notifications && !_foreground) {
      keepAliveEnabled = await AndroidPlatform.startKeepAlive(
        desktopName: active.first.name,
      );
    } else {
      await AndroidPlatform.stopKeepAlive();
      keepAliveEnabled = false;
    }
  }

  (String, int)? _parseHostPort(String input) {
    final value = input.trim();
    final idx = value.lastIndexOf(':');
    if (idx <= 0) return null;
    final host = value.substring(0, idx).trim();
    final port = int.tryParse(value.substring(idx + 1).trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    return (host, port);
  }

  // --------------------------------------------------------------- settings ---

  Future<void> setTheme(AppThemeChoice choice) async {
    themeChoice = choice;
    await runtime!.settings.setTheme(choice);
    notifyListeners();
  }

  Future<void> setNotifications(bool value) async {
    notifications = value;
    await runtime!.settings.setNotificationsEnabled(value);
    if (isPhone) await _syncKeepAlive();
    notifyListeners();
  }

  Future<void> setCleanLinks(bool value) async {
    cleanLinks = value;
    await runtime!.settings.setCleanLinks(value);
    notifyListeners();
  }

  Future<void> setShareAction(ShareDefaultAction action) async {
    shareAction = action;
    await runtime!.settings.setShareDefaultAction(action);
    notifyListeners();
  }

  Future<void> setPaused(bool value) async {
    paused = value;
    if (value) {
      await runtime!.pause();
    } else {
      await runtime!.resume();
    }
    desktopHooks.onPaused?.call(value);
    await _syncKeepAlive();
    notifyListeners();
  }

  Future<void> retryNow() async {
    runtime?.retryNow();
    notifyListeners();
  }

  Future<void> unpair() async {
    await runtime!.unpair();
    peers = await runtime!.peers.list();
    await _syncKeepAlive();
    toast = 'Unpaired.';
    notifyListeners();
  }

  Future<void> revokePeer(String peerId) async {
    await runtime!.revokePeer(peerId);
    peers = await runtime!.peers.list();
    toast = 'Device removed.';
    notifyListeners();
  }

  Future<void> setHideOnBlur(bool value) async {
    hideOnBlur = value;
    await runtime!.settings.setBool('desktop.hide_on_blur', value);
    await desktopHooks.onHideOnBlurChanged?.call(value);
    notifyListeners();
  }

  Future<void> setAutostart(bool value) async {
    if (desktopHooks.setAutostart == null) return;
    await desktopHooks.setAutostart!(value);
    autostart = value;
    notifyListeners();
  }

  Future<String?> exportNotepad({required bool markdown}) async {
    try {
      final doc = markdown
          ? await runtime!.exportService.markdown()
          : await runtime!.exportService.json();
      await paths.ensureExportDir();
      final file = File(p.join(paths.exportDir.path, doc.fileName));
      await file.writeAsString(doc.content, flush: true);
      toast = 'Exported to ${file.path}';
      notifyListeners();
      return file.path;
    } on Object catch (e) {
      toast = _messageFor(e);
      notifyListeners();
      return null;
    }
  }

  Future<void> clearAllData() async {
    final rt = runtime!;
    await rt.db.transaction(() async {
      await rt.db.customStatement('DELETE FROM peer_delivery');
      await rt.db.customStatement('DELETE FROM applied_remote');
      await rt.db.customStatement('DELETE FROM change_log');
      await rt.db.customStatement('DELETE FROM items_fts');
      await rt.db.customStatement('DELETE FROM items');
      await rt.db.customStatement('DELETE FROM categories');
      await rt.db.customStatement('DELETE FROM quarantine');
      await rt.db.customStatement('DELETE FROM peers');
      await rt.db.customStatement("DELETE FROM settings WHERE key NOT IN "
          "('device.id','device.name','device.kind')");
    });
    await rt.notepad.ensureInbox();
    await rt.notifier.clear();
    peers = const <Peer>[];
    selectedCategoryId = Category.inboxId;
    searchQuery = '';
    await refresh();
    toast = 'All TwinDrop data cleared on this device.';
    notifyListeners();
  }

  Future<String?> testConnection() async {
    final peer = activePeer;
    if (peer == null) return 'No paired desktop.';
    final host = peer.lastHost;
    final port = peer.lastPort;
    if (host == null || port == null) return 'No known address yet.';
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 4));
      socket.destroy();
      return 'Reached $host:$port.';
    } on Object catch (e) {
      return 'Could not reach $host:$port (${e.runtimeType}).';
    }
  }

  Future<void> setManualAddress(String hostPort) async {
    final parsed = _parseHostPort(hostPort);
    if (parsed == null) {
      toast = 'Enter an address like 192.168.1.23:47321.';
    } else {
      runtime!.connection?.setManualAddress(parsed.$1, parsed.$2);
      toast = 'Using ${parsed.$1}:${parsed.$2}.';
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ share ---

  Future<void> _importPendingShares() async {
    if (!isPhone) return;
    try {
      final pending = await AndroidPlatform.readShareQueue();
      final acked = <String>[];
      for (final share in pending) {
        final id = share['shareId'] as String?;
        final text = share['text'] as String?;
        if (id == null || text == null) continue;
        try {
          await runtime!.importNativeShare(
            shareId: id,
            text: text,
            sourceApp: share['sourcePackage'] as String?,
          );
        } on ValidationError {
          // Already imported: ack below.
        } on Object catch (e) {
          _logger.warn('share import failed', fields: {'error': e.runtimeType});
          continue;
        }
        acked.add(id);
      }
      if (acked.isNotEmpty) await AndroidPlatform.ackShares(acked);
      if (pending.isNotEmpty) await _loadNotepad();
    } on Object catch (e) {
      _logger.debug('share queue unavailable', fields: {'error': e.runtimeType});
    }
  }

  Future<void> importLaunchShare() async {
    await _importPendingShares();
    notifyListeners();
  }

  void clearToast() {
    toast = null;
    notifyListeners();
  }

  /// Shows a short confirmation. The message never contains message text, a
  /// full URL, a token or a pairing payload (`docs/08` §Logging).
  void showToast(String message) {
    toast = message;
    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is TwinDropError) return error.message;
    if (error is FormatException) return error.message;
    return 'Something went wrong. Try again.';
  }

  void _publishStatus() {
    desktopHooks.onStatus?.call(
      label: _statusLabel(status),
      connected: status.isOnline,
      unread: unreadChat,
    );
  }

  String _statusLabel(ConnectionStatus value) {
    switch (value) {
      case ConnectionStatus.unpaired:
        return 'Not paired';
      case ConnectionStatus.pairing:
        return 'Pairing';
      case ConnectionStatus.searching:
        return 'Searching';
      case ConnectionStatus.connecting:
        return 'Connecting';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.syncing:
        return 'Syncing';
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.paused:
        return 'Paused';
      case ConnectionStatus.removed:
        return 'Removed';
    }
  }

  @override
  void dispose() {
    _revisionSub?.cancel();
    _statusSub?.cancel();
    _peersSub?.cancel();
    _pairingReqSub?.cancel();
    _pairingTimer?.cancel();
    _searchDebounce?.cancel();
    _refreshDebounce?.cancel();
    runtime?.dispose();
    super.dispose();
  }
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String ref) => _storage.read(key: ref);

  @override
  Future<void> write(String ref, String value) =>
      _storage.write(key: ref, value: value);

  @override
  Future<void> delete(String ref) => _storage.delete(key: ref);
}

class _NoopNotifier implements CoreNotifier {
  const _NoopNotifier();

  @override
  Future<void> clear() async {}

  @override
  Future<void> onConnectionChanged(ConnectionStatus status) async {}

  @override
  Future<void> onIncomingItem(Item item) async {}
}
