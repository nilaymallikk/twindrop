import 'dart:async';

import 'package:flutter/material.dart';
import 'package:twindrop_core/core.dart';

import 'bootstrap/app_paths.dart';
import 'platform/android/android_platform.dart';
import 'state/app_controller.dart';
import 'theme/context_ext.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/buttons.dart';
import 'widgets/primitives.dart';
import 'widgets/td_icons.dart';

/// Share-panel engine (docs/06 §1, `SHARE-003`).
///
/// Runs in its own warm isolate behind the translucent panel the Android share
/// sheet shows. The shared payload is already in the native queue when this
/// starts, so the panel can render "Saved to Inbox" immediately — no database
/// and no network on the critical path (`SHARE-009`).
///
/// The panel only touches the database when the user asks for something that
/// needs it (send as chat, change category).
void runSharePanel() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SharePanelApp());
}

class SharePanelApp extends StatefulWidget {
  const SharePanelApp({super.key});

  @override
  State<SharePanelApp> createState() => _SharePanelAppState();
}

class _SharePanelAppState extends State<SharePanelApp> {
  Map<String, dynamic> _payload = const <String, dynamic>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AndroidPlatform.listenPanelChanges(_onPanelPayload);
    unawaited(_load());
  }

  Future<void> _load() async {
    final payload = await AndroidPlatform.getPanelPayload();
    if (!mounted) return;
    setState(() => _payload = payload);
  }

  void _onPanelPayload(Map<String, dynamic> payload) {
    if (!mounted) return;
    setState(() => _payload = payload);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TwinDrop',
      debugShowCheckedModeBanner: false,
      theme: buildTdTheme(
        choice: AppThemeChoice.dark,
        platformBrightness: Brightness.dark,
      ),
      home: SharePanelView(
        payload: _payload,
        busy: _busy,
        onUndo: _undo,
        onAlsoSendAsChat: _alsoSendAsChat,
        onChangeCategory: _changeCategory,
      ),
    );
  }

  String get _shareId => (_payload['shareId'] as String?) ?? '';
  String get _text => (_payload['text'] as String?) ?? '';

  Future<void> _undo() async {
    if (_shareId.isEmpty) return;
    setState(() => _busy = true);
    // Removing the queued entry means the item is never created, so the
    // main app has nothing left to import.
    await AndroidPlatform.ackShares(<String>[_shareId]);
    await AndroidPlatform.finishPanel('undo');
  }

  Future<void> _alsoSendAsChat() async {
    if (_shareId.isEmpty) return;
    setState(() => _busy = true);
    final runtime = await _openRuntime();
    if (runtime == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await runtime.importNativeShare(
      shareId: _shareId,
      text: _text,
      sourceApp: _payload['sourcePackage'] as String?,
      action: ShareDefaultAction.chat,
    );
    await AndroidPlatform.ackShares(<String>[_shareId]);
    await runtime.dispose();
    await AndroidPlatform.finishPanel('chat');
  }

  Future<void> _changeCategory() async {
    if (_shareId.isEmpty) return;
    setState(() => _busy = true);
    final runtime = await _openRuntime();
    if (runtime == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final result = await runtime.importNativeShare(
      shareId: _shareId,
      text: _text,
      sourceApp: _payload['sourcePackage'] as String?,
      action: ShareDefaultAction.notepad,
    );
    final categories = await runtime.notepad.listCategories();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.td.surface,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final category in categories)
              ListTile(
                title: Text(category.name),
                onTap: () => Navigator.of(sheetContext).pop(category.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && result.item != null) {
      await runtime.shareIngest.changeCategory(result.item!, chosen);
    }
    await AndroidPlatform.ackShares(<String>[_shareId]);
    await runtime.dispose();
    await AndroidPlatform.finishPanel('category');
  }

  Future<CoreRuntime?> _openRuntime() async {
    try {
      final paths = await AppPaths.resolve();
      return await CoreRuntime.open(
        platform: CorePlatform.phone,
        deviceName: 'TwinDrop',
        dataDir: paths.supportDir.path,
        tokenStore: SecureTokenStore(),
      );
    } on Object {
      return null;
    }
  }
}

/// The compact card itself.
class SharePanelView extends StatelessWidget {
  const SharePanelView({
    super.key,
    required this.payload,
    required this.busy,
    required this.onUndo,
    required this.onAlsoSendAsChat,
    required this.onChangeCategory,
  });

  final Map<String, dynamic> payload;
  final bool busy;
  final VoidCallback onUndo;
  final VoidCallback onAlsoSendAsChat;
  final VoidCallback onChangeCategory;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final text = (payload['text'] as String?) ?? '';
    final source = (payload['sourcePackage'] as String?) ?? '';
    final paired = (payload['paired'] as bool?) ?? false;
    final desktopName = (payload['desktopName'] as String?) ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(TdSpace.s12),
          padding: const EdgeInsets.all(TdSpace.s16),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.hairline),
            borderRadius: TdRadius.allLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  TdIcon(TdIcons.check, size: 18, color: tokens.ok),
                  const SizedBox(width: TdSpace.s8),
                  Expanded(
                    child: Text(
                      'Saved to Inbox',
                      style: context.tdType.cardTitle,
                    ),
                  ),
                ],
              ),
              if (text.isNotEmpty) ...<Widget>[
                const SizedBox(height: TdSpace.s8),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tdType.body,
                ),
              ],
              const SizedBox(height: TdSpace.s8),
              Text(
                paired
                    ? 'Will sync to ${desktopName.isEmpty ? 'the desktop' : desktopName}.'
                    : 'Will sync when the desktop is online.',
                style: context.tdType.meta,
              ),
              const SizedBox(height: TdSpace.s12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TdButton(
                      label: 'Undo',
                      variant: TdButtonVariant.tertiary,
                      onPressed: busy ? null : onUndo,
                    ),
                  ),
                  const SizedBox(width: TdSpace.s8),
                  Expanded(
                    child: TdButton(
                      label: 'Change category',
                      variant: TdButtonVariant.secondary,
                      onPressed: busy ? null : onChangeCategory,
                    ),
                  ),
                  const SizedBox(width: TdSpace.s8),
                  Expanded(
                    child: TdButton(
                      label: 'Also send as chat',
                      variant: TdButtonVariant.secondary,
                      onPressed: busy ? null : onAlsoSendAsChat,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
