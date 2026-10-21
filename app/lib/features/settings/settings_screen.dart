import 'package:flutter/material.dart';
import 'package:twindrop_core/models/enums.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/settings_rows.dart';
import '../../widgets/states.dart';
import '../../widgets/status.dart';
import '../../widgets/td_icons.dart';

/// Settings for both platforms: device state, sharing, notifications,
/// appearance, background keep-alive, desktop, data and about.
///
/// Unsupported rows stay visible and disabled with the reason, so a control is
/// never dead without an explanation (AGENTS rule 7). Destructive actions are
/// confirmed here; the host performs them.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.status,
    this.peerName,
    this.peerLabel,
    this.deviceId,
    this.deviceName,
    this.localAddresses = const <String>[],
    this.lastSyncLabel,
    this.queueCount = 0,
    this.serverState,
    this.ipPort,
    required this.themeChoice,
    required this.onThemeChanged,
    required this.notifications,
    required this.onNotificationsChanged,
    this.notificationsSupported = true,
    required this.shareAction,
    required this.onShareActionChanged,
    required this.cleanLinks,
    required this.onCleanLinksChanged,
    required this.paused,
    required this.onPauseChanged,
    this.onRevoke,
    this.onUnpair,
    this.onRetryNow,
    this.onExportMarkdown,
    this.onExportJson,
    this.onClearData,
    this.onOpenDiagnostics,
    this.onPairAgain,
    this.keepAliveSupported = false,
    this.keepAliveEnabled = false,
    this.onKeepAliveChanged,
    this.batteryOptimized = true,
    this.onBatterySettings,
    this.autostartSupported = false,
    this.autostart = false,
    this.onAutostartChanged,
    this.hideOnBlur = true,
    this.onHideOnBlurChanged,
    this.quickSendCommand,
    this.onCopyQuickSend,
    this.appVersion = '0.1.0',
    this.isDesktop = false,
    this.trayAvailable = true,
    this.quarantineCount = 0,
    this.onOpenQuarantine,
  });

  final ConnectionStatus status;
  final String? peerName;
  final String? peerLabel;
  final String? deviceId;
  final String? deviceName;
  final List<String> localAddresses;
  final String? lastSyncLabel;
  final int queueCount;
  final String? serverState;
  final String? ipPort;
  final AppThemeChoice themeChoice;
  final ValueChanged<AppThemeChoice> onThemeChanged;
  final bool notifications;
  final ValueChanged<bool> onNotificationsChanged;
  final bool notificationsSupported;
  final ShareDefaultAction shareAction;
  final ValueChanged<ShareDefaultAction> onShareActionChanged;
  final bool cleanLinks;
  final ValueChanged<bool> onCleanLinksChanged;
  final bool paused;
  final ValueChanged<bool> onPauseChanged;
  final VoidCallback? onRevoke;
  final VoidCallback? onUnpair;
  final VoidCallback? onRetryNow;
  final VoidCallback? onExportMarkdown;
  final VoidCallback? onExportJson;
  final VoidCallback? onClearData;
  final VoidCallback? onOpenDiagnostics;
  final VoidCallback? onPairAgain;
  final bool keepAliveSupported;
  final bool keepAliveEnabled;
  final ValueChanged<bool>? onKeepAliveChanged;
  final bool batteryOptimized;
  final VoidCallback? onBatterySettings;
  final bool autostartSupported;
  final bool autostart;
  final ValueChanged<bool>? onAutostartChanged;
  final bool hideOnBlur;
  final ValueChanged<bool>? onHideOnBlurChanged;
  final String? quickSendCommand;
  final VoidCallback? onCopyQuickSend;
  final String appVersion;
  final bool isDesktop;
  final bool trayAvailable;
  final int quarantineCount;
  final VoidCallback? onOpenQuarantine;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return ColoredBox(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TdScreenHeader(
            title: 'Settings',
            subtitle: Text(
              peerLabel ?? deviceName ?? 'This device',
              style: context.tdType.meta.copyWith(color: tokens.muted),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(TdSpace.s16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: TdContentWidth.settings,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _section(context, 'DEVICE', _deviceRows(context)),
                      _section(context, 'SHARING', _sharingRows(context)),
                      _section(
                        context,
                        'NOTIFICATIONS',
                        _notificationRows(context),
                      ),
                      _section(context, 'APPEARANCE', _appearanceRows(context)),
                      if (!isDesktop)
                        _section(
                          context,
                          'BACKGROUND',
                          _backgroundRows(context),
                        ),
                      if (isDesktop)
                        _section(context, 'DESKTOP', _desktopRows(context)),
                      _section(context, 'DATA', _dataRows(context)),
                      _section(context, 'ABOUT', _aboutRows(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String label, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TdSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TdSectionLabel(label),
          TdGroup(children: <Widget>[tdGroupDividers(rows)]),
        ],
      ),
    );
  }

  List<Widget> _deviceRows(BuildContext context) {
    final rows = <Widget>[
      TdSettingsRow(
        label: deviceName ?? 'This device',
        description: peerName == null
            ? 'Not paired'
            : 'Paired with $peerName',
        value: deviceId,
        monoValue: true,
      ),
      TdSettingsRow(
        label: 'Status',
        trailing: TdStatus(status: status),
      ),
      if (ipPort != null)
        TdSettingsRow(
          label: 'Address',
          value: ipPort,
          monoValue: true,
        ),
      if (localAddresses.isNotEmpty)
        TdSettingsRow(
          label: 'Local addresses',
          value: localAddresses.join(', '),
          monoValue: true,
        ),
      if (lastSyncLabel != null)
        TdSettingsRow(label: 'Last sync', value: lastSyncLabel),
      TdSettingsRow(
        label: 'Waiting to sync',
        value: queueCount == 1 ? '1 item' : '$queueCount items',
      ),
      TdSettingsRow(
        label: 'Server',
        value: serverState ?? 'Stopped',
      ),
      TdSettingsRow(
        label: 'Retry now',
        description: 'Try to reach your desktop immediately.',
        onTap: onRetryNow,
        enabled: onRetryNow != null,
        disabledReason: 'There is nothing to retry right now.',
      ),
      TdToggleRow(
        label: 'Pause syncing',
        description: 'Queued items stay on this device until you resume.',
        value: paused,
        onChanged: onPauseChanged,
      ),
      if (onPairAgain != null)
        TdSettingsRow(
          label: 'Pair again',
          description: 'Start a new pairing session with a desktop.',
          onTap: onPairAgain,
        ),
      if (onRevoke != null)
        TdSettingsRow(
          label: 'Remove this phone',
          description: 'It loses access immediately. Its local data stays '
              'until you clear it on the phone.',
          destructive: true,
          onTap: () => _confirmRevoke(context),
        ),
      if (onUnpair != null)
        TdSettingsRow(
          label: 'Unpair this device',
          description: 'Stop syncing and forget the pairing.',
          destructive: true,
          onTap: () => _confirmUnpair(context),
        ),
    ];
    return rows;
  }

  List<Widget> _sharingRows(BuildContext context) {
    return <Widget>[
      for (final action in ShareDefaultAction.values)
        TdChoiceRow(
          label: _shareActionLabel(action),
          description: _shareActionDescription(action),
          selected: shareAction == action,
          onSelected: () => onShareActionChanged(action),
        ),
      TdToggleRow(
        label: 'Clean Instagram links',
        description: 'Remove tracking parameters from shared Instagram and '
            'Reels links.',
        value: cleanLinks,
        onChanged: onCleanLinksChanged,
      ),
    ];
  }

  List<Widget> _notificationRows(BuildContext context) {
    return <Widget>[
      TdToggleRow(
        label: 'Notifications',
        description: notificationsSupported
            ? 'Show a notification when a message arrives.'
            : 'Notifications are not available on this platform.',
        value: notifications,
        onChanged:
            notificationsSupported ? onNotificationsChanged : null,
        disabledReason: notificationsSupported
            ? null
            : 'Notifications are not available on this platform.',
      ),
    ];
  }

  List<Widget> _appearanceRows(BuildContext context) {
    return <Widget>[
      for (final choice in AppThemeChoice.values)
        TdChoiceRow(
          label: _themeLabel(choice),
          description: _themeDescription(choice),
          selected: themeChoice == choice,
          onSelected: () => onThemeChanged(choice),
        ),
    ];
  }

  List<Widget> _backgroundRows(BuildContext context) {
    return <Widget>[
      TdToggleRow(
        label: 'Keep the connection open',
        description: 'Runs one idle connection and shows a notification so '
            'messages arrive while TwinDrop is closed.',
        value: keepAliveEnabled,
        onChanged: keepAliveSupported ? onKeepAliveChanged : null,
        disabledReason: keepAliveSupported
            ? null
            : 'Background keep-alive is available on Android only.',
      ),
      TdSettingsRow(
        label: 'Battery optimization',
        description: batteryOptimized
            ? 'Android may close the connection to save power.'
            : 'TwinDrop is excluded from battery optimization.',
        value: batteryOptimized ? 'Optimized' : 'Not optimized',
        onTap: onBatterySettings,
        enabled: onBatterySettings != null,
        disabledReason:
            'Battery settings are only available on Android devices.',
      ),
    ];
  }

  List<Widget> _desktopRows(BuildContext context) {
    return <Widget>[
      TdToggleRow(
        label: 'Start at login',
        description: autostartSupported
            ? 'Open TwinDrop when you sign in.'
            : 'Autostart is only available in the Linux desktop app.',
        value: autostart,
        onChanged: autostartSupported ? onAutostartChanged : null,
        disabledReason: autostartSupported
            ? null
            : 'Autostart is only available in the Linux desktop app.',
      ),
      TdToggleRow(
        label: 'Hide when the window loses focus',
        description: trayAvailable
            ? 'The window hides to the tray instead of closing.'
            : 'Your desktop is not showing tray icons, so TwinDrop stays in '
                'a normal window.',
        value: hideOnBlur,
        onChanged: trayAvailable ? onHideOnBlurChanged : null,
        disabledReason: trayAvailable
            ? null
            : 'No tray host was detected on this desktop.',
      ),
      TdSettingsRow(
        label: 'Tray icon',
        value: trayAvailable ? 'Available' : 'Not available',
        description: trayAvailable
            ? null
            : 'Install a tray extension or use the app window.',
      ),
      TdSettingsRow(
        label: 'Quick-send command',
        description: 'Bind this command to any desktop shortcut.',
        value: quickSendCommand,
        monoValue: true,
        enabled: quickSendCommand != null,
        disabledReason: 'The quick-send command is not available in this '
            'build.',
        trailing: onCopyQuickSend == null
            ? null
            : TdIconButton(
                icon: TdIcons.copy,
                label: 'Copy command',
                tooltip: 'Copy command',
                onPressed: onCopyQuickSend,
              ),
      ),
    ];
  }

  List<Widget> _dataRows(BuildContext context) {
    return <Widget>[
      TdSettingsRow(
        label: 'Export as Markdown',
        description: 'One file with every note.',
        onTap: onExportMarkdown,
        enabled: onExportMarkdown != null,
        disabledReason: 'Export is unavailable right now.',
      ),
      TdSettingsRow(
        label: 'Export as JSON',
        description: 'A machine-readable copy of your notes.',
        onTap: onExportJson,
        enabled: onExportJson != null,
        disabledReason: 'Export is unavailable right now.',
      ),
      TdSettingsRow(
        label: 'Quarantined items',
        description: quarantineCount == 0
            ? 'Nothing has been quarantined.'
            : 'Items that failed validation and were kept aside.',
        value: '$quarantineCount',
        onTap: onOpenQuarantine,
        enabled: quarantineCount > 0 && onOpenQuarantine != null,
        disabledReason: quarantineCount == 0
            ? 'Nothing has been quarantined.'
            : 'The quarantine view is unavailable right now.',
      ),
      TdSettingsRow(
        label: 'Clear all data',
        description: 'Deletes messages, notes and settings on this device.',
        destructive: true,
        onTap: () => _confirmClearData(context),
        enabled: onClearData != null,
        disabledReason: 'Clearing data is unavailable right now.',
      ),
    ];
  }

  List<Widget> _aboutRows(BuildContext context) {
    return <Widget>[
      TdSettingsRow(label: 'Version', value: appVersion, monoValue: true),
      TdSettingsRow(
        label: 'What this is',
        description: 'TwinDrop moves text and links between your own phone and '
            'your own desktop over your own Wi-Fi. There is no account, no '
            'cloud and no analytics.',
      ),
      TdSettingsRow(
        label: 'Your data',
        description: 'Messages and notes stay on this device and on the paired '
            'desktop. Nothing is sent anywhere else.',
      ),
      TdSettingsRow(
        label: 'Open-source licences',
        description: 'IBM Plex fonts are under the SIL Open Font License. '
            'Flutter and the plugins keep their own licences.',
      ),
      TdSettingsRow(
        label: 'Diagnostics',
        description: 'Addresses, pin state, and connection tests.',
        onTap: onOpenDiagnostics,
        enabled: onOpenDiagnostics != null,
        disabledReason: 'Diagnostics are unavailable right now.',
      ),
    ];
  }

  static String _shareActionLabel(ShareDefaultAction action) {
    switch (action) {
      case ShareDefaultAction.notepad:
        return 'Save to Notepad';
      case ShareDefaultAction.chat:
        return 'Send as chat';
      case ShareDefaultAction.ask:
        return 'Ask each time';
    }
  }

  static String _shareActionDescription(ShareDefaultAction action) {
    switch (action) {
      case ShareDefaultAction.notepad:
        return 'Shared text and links go straight to Inbox.';
      case ShareDefaultAction.chat:
        return 'Shared text and links open in the chat composer.';
      case ShareDefaultAction.ask:
        return 'Choose what to do after every share.';
    }
  }

  static String _themeLabel(AppThemeChoice choice) {
    switch (choice) {
      case AppThemeChoice.dark:
        return 'Dark';
      case AppThemeChoice.light:
        return 'Light';
      case AppThemeChoice.system:
        return 'System';
      case AppThemeChoice.black:
        return 'Black';
    }
  }

  static String _themeDescription(AppThemeChoice choice) {
    switch (choice) {
      case AppThemeChoice.dark:
        return 'Dark is the default.';
      case AppThemeChoice.light:
        return 'Warm paper background with dark ink.';
      case AppThemeChoice.system:
        return 'Follow the system setting.';
      case AppThemeChoice.black:
        return 'True black for OLED screens.';
    }
  }

  Future<void> _confirmRevoke(BuildContext context) async {
    final confirmed = await showTdConfirmDialog(
      context,
      title: 'Remove this phone?',
      message: 'It will have to pair again to sync. Its local data stays on '
          'the phone until you clear it there.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) onRevoke?.call();
  }

  Future<void> _confirmUnpair(BuildContext context) async {
    final confirmed = await showTdConfirmDialog(
      context,
      title: 'Unpair this device?',
      message: 'Sync stops and the pairing is forgotten. Local data stays '
          'until you clear it.',
      confirmLabel: 'Unpair',
      destructive: true,
    );
    if (confirmed) onUnpair?.call();
  }

  Future<void> _confirmClearData(BuildContext context) async {
    final confirmed = await showTdConfirmDialog(
      context,
      title: 'Clear all data?',
      message: 'Messages, notes and settings on this device are deleted. '
          'Other devices keep their copies. This cannot be undone.',
      confirmLabel: 'Clear data',
      destructive: true,
    );
    if (confirmed) onClearData?.call();
  }
}
