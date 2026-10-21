import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/features/chat/chat_popup.dart';
import 'package:twindrop/features/chat/chat_screen.dart';
import 'package:twindrop/features/models.dart';
import 'package:twindrop/features/notepad/notepad_screen.dart';
import 'package:twindrop/features/pairing/desktop_pairing_screen.dart';
import 'package:twindrop/features/pairing/phone_onboarding_screen.dart';
import 'package:twindrop/features/settings/diagnostics_screen.dart';
import 'package:twindrop/features/settings/settings_screen.dart';
import 'package:twindrop/share_panel_main.dart';
import 'package:twindrop/theme/theme.dart';
import 'package:twindrop_core/core.dart';

/// Golden tests for both appearances (DES-001).
///
/// The golden files are regenerated with:
///   flutter test --update-goldens test/golden_test.dart
/// and are reviewed by eye against the anti-slop rules in `docs/13` §9.
///
/// `flutter_test` replaces every font with the Ahem test font, which draws
/// boxes. The real bundled IBM Plex faces are loaded here so the golden shows
/// the typography that actually ships (DES-003).
Future<void> _loadBundledFonts() async {
  Future<void> load(String family, String asset) async {
    final loader = FontLoader(family)..addFont(rootBundle.load(asset));
    await loader.load();
  }

  await load('IBM Plex Sans', 'assets/fonts/IBMPlexSans-Regular.ttf');
  await load('IBM Plex Sans', 'assets/fonts/IBMPlexSans-Medium.ttf');
  await load('IBM Plex Sans', 'assets/fonts/IBMPlexSans-SemiBold.ttf');
  await load('IBM Plex Mono', 'assets/fonts/IBMPlexMono-Regular.ttf');
}

/// The screenshot sizes the design gate asks for (docs/13 §11).
const Size desktopSize = Size(1280, 800);
const Size phoneSize = Size(393, 852);

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required AppThemeChoice choice,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // The theme mode has to follow the choice explicitly: the test platform
      // reports a dark brightness, so ThemeMode.system would always pick dark.
      themeMode: choice == AppThemeChoice.light
          ? ThemeMode.light
          : ThemeMode.dark,
      theme: buildTdTheme(
        choice: choice,
        platformBrightness:
            choice == AppThemeChoice.light ? Brightness.light : Brightness.dark,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

ChatEntry _entry(
  String id,
  String text, {
  bool mine = true,
  DeliveryState delivery = DeliveryState.delivered,
  String? url,
}) {
  return ChatEntry(
    item: Item(
      id: id,
      type: ItemType.message,
      kind: ItemKind.text,
      text: text,
      url: url,
      createdAt: 1700000000000,
      originDevice: '01a15d25-ebdb-7ce7-80a3-f05411833218',
      originName: 'Desk',
      contentHash: 'h$id',
      contentHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
      metaHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
    ),
    mine: mine,
    delivery: delivery,
  );
}

Item _note(String id, String title, String text, {bool pinned = false}) {
  return Item(
    id: id,
    type: ItemType.note,
    kind: ItemKind.text,
    title: title,
    text: text,
    createdAt: 1700000000000,
    originDevice: '01a15d25-ebdb-7ce7-80a3-f05411833218',
    originName: 'Desk',
    contentHash: 'h$id',
    contentHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
    metaHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
    pinned: pinned,
    categoryId: 'inbox',
  );
}

const Category inbox = Category(
  id: 'inbox',
  name: 'Inbox',
  normalizedName: 'inbox',
  sortOrder: 0,
  isInbox: true,
  metaHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
);

const Category work = Category(
  id: 'work',
  name: 'Work',
  normalizedName: 'work',
  sortOrder: 1,
  isInbox: false,
  metaHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
);

Widget _chat() => ChatScreen(
      entries: <ChatEntry>[
        _entry('m1', 'Shared a link from the phone.',
            url: 'https://example.com/a'),
        _entry('m2', 'And a reply from the desktop.', mine: false),
        _entry('m3', 'Queued while the desktop was away.',
            delivery: DeliveryState.queued),
      ],
      status: ConnectionStatus.connected,
      peerName: 'Phone',
      onSend: (_) {},
      onSaveToNotepad: (_) {},
    );

Widget _notepad() => NotepadScreen(
      categories: const <Category>[inbox, work],
      notes: <Item>[
        _note('n1', 'Release checklist', 'Ship the AppImage and the APK.'),
        _note('n2', 'Reel to watch', 'https://example.com/reel', pinned: true),
      ],
      selectedCategoryId: 'inbox',
      categoryNames: const <String, String>{'inbox': 'Inbox', 'work': 'Work'},
      showSidebar: true,
    );

Widget _settings() => SettingsScreen(
      status: ConnectionStatus.connected,
      peerName: 'Phone',
      peerLabel: '192.168.1.23:47321',
      deviceId: '01a15d25-ebdb-7ce7-80a3-f05411833218',
      deviceName: 'fedora',
      localAddresses: const <String>['192.168.1.23'],
      lastSyncLabel: '2 minutes ago',
      queueCount: 0,
      serverState: 'Running on port 47321',
      ipPort: '192.168.1.23:47321',
      themeChoice: AppThemeChoice.dark,
      onThemeChanged: (_) {},
      notifications: true,
      onNotificationsChanged: (_) {},
      shareAction: ShareDefaultAction.notepad,
      onShareActionChanged: (_) {},
      cleanLinks: true,
      onCleanLinksChanged: (_) {},
      paused: false,
      onPauseChanged: (_) {},
      appVersion: '1.0.0',
      isDesktop: true,
    );

Widget _diagnostics() => DiagnosticsScreen(
      localAddresses: const <String>['192.168.1.23'],
      peerLabel: 'Phone',
      peerLastAddress: '192.168.1.23:47321',
      mdnsSummary: 'Announcing',
      pinState: 'Pinned a1b2c3d4e5f6…',
      serverPort: 47321,
      firewallHint: 'sudo firewall-cmd --add-port=47321/tcp',
      onTestConnection: () async => 'Reachable in 12 ms.',
      onManualAddress: (_) async {},
      onRetry: () async {},
    );

Widget _pairing() => DesktopPairingScreen(
      data: const DesktopPairingData(
        stage: DesktopPairingStage.approval,
        requestDeviceName: 'Pixel 8',
        requestPlatform: 'android',
        confirmationCode: '4271',
        manualAddress: '192.168.1.23:47321',
      ),
      onStart: () {},
      onCancel: () {},
      onApprove: (_) {},
      onReject: (_) {},
    );

Widget _onboarding() => PhoneOnboardingScreen(
      data: const PhoneOnboardingData(
        stage: PhoneOnboardingStage.welcome,
      ),
      onStartScan: () {},
      onSubmitQr: (_) {},
      onManualEntry: () {},
      onConfirmFingerprint: (_) {},
      onSubmitManual: (_, __) {},
      onPermissionDecided: (_) {},
      onSkip: (_) {},
      onCancel: () {},
      onDone: () async {},
    );

Widget _sharePanel() => const SharePanelView(
      payload: <String, dynamic>{
        'shareId': 's-1',
        'text': 'https://example.com/reel',
        'sourcePackage': 'com.instagram.android',
        'paired': true,
        'desktopName': 'fedora',
      },
      busy: false,
      onUndo: _noop,
      onAlsoSendAsChat: _noop,
      onChangeCategory: _noop,
    );

Widget _popup() => ChatPopup(
      entries: <ChatEntry>[
        _entry('m1', 'Shared a link from the phone.', url: 'https://example.com/a'),
        _entry('m2', 'And a reply from the desktop.', mine: false),
      ],
      status: ConnectionStatus.connected,
      peerName: 'Phone',
      onOpenApp: () {},
      onSend: (_) {},
      onSaveToNotepad: (_) {},
    );

void _noop() {}

void main() {
  setUpAll(_loadBundledFonts);

  for (final theme in const <AppThemeChoice>[
    AppThemeChoice.dark,
    AppThemeChoice.light,
  ]) {
    final label = theme == AppThemeChoice.dark ? 'dark' : 'light';

    group('$label theme', () {
      testWidgets('chat — desktop 1280x800', (tester) async {
        await _pumpAt(tester, _chat(), size: desktopSize, choice: theme);
        await expectLater(
          find.byType(ChatScreen),
          matchesGoldenFile('goldens/chat_${label}_desktop.png'),
        );
      });

      testWidgets('chat — phone 393x852', (tester) async {
        await _pumpAt(tester, _chat(), size: phoneSize, choice: theme);
        await expectLater(
          find.byType(ChatScreen),
          matchesGoldenFile('goldens/chat_${label}_phone.png'),
        );
      });

      testWidgets('notepad — desktop 1280x800', (tester) async {
        await _pumpAt(tester, _notepad(), size: desktopSize, choice: theme);
        await expectLater(
          find.byType(NotepadScreen),
          matchesGoldenFile('goldens/notepad_${label}_desktop.png'),
        );
      });

      testWidgets('settings — desktop 1280x800', (tester) async {
        await _pumpAt(tester, _settings(), size: desktopSize, choice: theme);
        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile('goldens/settings_${label}_desktop.png'),
        );
      });

      testWidgets('diagnostics — desktop 1280x800', (tester) async {
        await _pumpAt(tester, _diagnostics(), size: desktopSize, choice: theme);
        await expectLater(
          find.byType(DiagnosticsScreen),
          matchesGoldenFile('goldens/diagnostics_${label}_desktop.png'),
        );
      });

      testWidgets('pairing — desktop 1280x800', (tester) async {
        await _pumpAt(tester, _pairing(), size: desktopSize, choice: theme);
        await expectLater(
          find.byType(DesktopPairingScreen),
          matchesGoldenFile('goldens/pairing_${label}_desktop.png'),
        );
      });

      testWidgets('onboarding — phone 393x852', (tester) async {
        await _pumpAt(tester, _onboarding(), size: phoneSize, choice: theme);
        await expectLater(
          find.byType(PhoneOnboardingScreen),
          matchesGoldenFile('goldens/onboarding_${label}_phone.png'),
        );
      });

      testWidgets('share panel — phone 393x852', (tester) async {
        await _pumpAt(tester, _sharePanel(), size: phoneSize, choice: theme);
        await expectLater(
          find.byType(SharePanelView),
          matchesGoldenFile('goldens/share_panel_${label}_phone.png'),
        );
      });

      testWidgets('popup — desktop 1280x800', (tester) async {
        await _pumpAt(tester, _popup(), size: desktopSize, choice: theme);
        await expectLater(
          find.byType(ChatPopup),
          matchesGoldenFile('goldens/popup_${label}_desktop.png'),
        );
      });
    });
  }
}
