// `Category` (flutter/foundation) would clash with the notepad's Category
// model; only the annotations are needed from foundation.
import 'package:flutter/foundation.dart' hide Category;
import 'package:twindrop_core/models/category.dart';
import 'package:twindrop_core/models/enums.dart';
import 'package:twindrop_core/models/item.dart';

/// Top-level sections in both the phone bottom navigation and the desktop
/// sidebar.
enum AppSection { chat, notepad, settings }

/// A chat message as the UI needs it: the persisted [item] plus the local
/// delivery state and sender side. No network or database access lives here.
@immutable
class ChatEntry {
  const ChatEntry({
    required this.item,
    required this.mine,
    this.delivery = DeliveryState.queued,
    this.deviceLabel,
  });

  final Item item;

  /// True when this device created the message.
  final bool mine;

  /// Local delivery state; only shown for [mine]. `Delivered` must come from a
  /// peer ack (MSG-006) — the UI renders whatever it is given.
  final DeliveryState delivery;

  /// Overrides the device label (defaults to the item's origin name).
  final String? deviceLabel;

  String get id => item.id;
  String get text => item.text;
  String? get url => item.url;
  String get label => deviceLabel ?? item.originName;
  int get createdAt => item.createdAt;
}

/// A draft produced by the note editor. Persistence is the caller's job.
@immutable
class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.text,
    required this.categoryId,
  });

  /// Empty string when the note has no title.
  final String title;
  final String text;
  final String categoryId;

  bool get isEmpty => title.trim().isEmpty && text.trim().isEmpty;
}

/// Result of the save-to-notepad sheet.
@immutable
class SaveToNotepadResult {
  const SaveToNotepadResult({required this.categoryId, this.title});

  final String categoryId;
  final String? title;
}

/// Category editing callbacks. Returning a message means "not saved"; the
/// screen shows it next to the field instead of closing the dialog.
@immutable
class CategoryActions {
  const CategoryActions({
    this.onCreate,
    this.onRename,
    this.onDelete,
    this.onReorder,
  });

  /// Creates a category from a trimmed name; returns an error message or null.
  final Future<String?> Function(String name)? onCreate;

  /// Renames a category; returns an error message or null.
  final Future<String?> Function(String categoryId, String name)? onRename;

  /// Deletes a category; returns false when deletion is not allowed (Inbox).
  final Future<bool> Function(String categoryId)? onDelete;

  /// Moves a category from one display index to another (Inbox stays first).
  final void Function(int from, int to)? onReorder;

  bool get canCreate => onCreate != null;
  bool get canEdit => onRename != null || onDelete != null || onReorder != null;
}

/// Deletion-undo state for the notepad. The screen renders an undo bar while
/// this is non-null; the host clears it when the 5 s window ends or Undo runs.
@immutable
class NotepadUndo {
  const NotepadUndo({
    required this.message,
    required this.onUndo,
    required this.onDismissed,
    this.actionLabel = 'Undo',
  });

  final String message;
  final String actionLabel;
  final VoidCallback onUndo;
  final VoidCallback onDismissed;
}

/// The notepad's visible list after search/filter. Sorting pinned-then-newest
/// is done by the screen because it is pure presentation.
@immutable
class NotepadData {
  const NotepadData({
    required this.categories,
    required this.notes,
    required this.categoryNames,
    this.selectedCategoryId = Category.inboxId,
  });

  final List<Category> categories;
  final List<Item> notes;

  /// Category id -> display name, used by the note meta row.
  final Map<String, String> categoryNames;
  final String selectedCategoryId;
}

/// A permission step shown during phone onboarding. TwinDrop asks for each one
/// separately and always offers Skip (docs/02 §1).
enum PhonePermission {
  notifications,
  background,
  battery;

  String get title {
    switch (this) {
      case PhonePermission.notifications:
        return 'Notifications';
      case PhonePermission.background:
        return 'Background connection';
      case PhonePermission.battery:
        return 'Battery';
    }
  }

  String get description {
    switch (this) {
      case PhonePermission.notifications:
        return 'See messages while TwinDrop is closed.';
      case PhonePermission.background:
        return 'Keep one idle connection open so messages arrive with the app '
            'closed. TwinDrop shows a notification while it runs.';
      case PhonePermission.battery:
        return 'Stop Android from closing the connection to save power.';
    }
  }
}

/// State of one permission step in onboarding.
@immutable
class PermissionStepState {
  const PermissionStepState({
    required this.permission,
    this.granted = false,
    this.skipped = false,
  });

  final PhonePermission permission;
  final bool granted;
  final bool skipped;

  bool get decided => granted || skipped;
}

/// Desktop pairing stages. The screen renders only what the state says; it
/// never starts a session or approves on its own.
enum DesktopPairingStage { idle, waitingForPhone, approval, connected, error }

@immutable
class DesktopPairingData {
  const DesktopPairingData({
    required this.stage,
    this.qrPayload,
    this.manualAddress,
    this.fingerprint,
    this.expiryLabel,
    this.requestId,
    this.requestDeviceName,
    this.requestPlatform,
    this.confirmationCode,
    this.connectedDeviceName,
    this.errorMessage,
    this.busy = false,
  });

  final DesktopPairingStage stage;

  /// Full QR payload from the pairing service. Never logged.
  final String? qrPayload;

  /// `host:port` for manual entry on the phone.
  final String? manualAddress;

  /// Short certificate fingerprint the phone compares (PAIR-008).
  final String? fingerprint;

  /// e.g. `4:32 left`.
  final String? expiryLabel;

  /// Id of the pending approval request. Required to approve or reject it.
  final String? requestId;

  /// Pending approval request details.
  final String? requestDeviceName;
  final String? requestPlatform;
  final String? confirmationCode;

  final String? connectedDeviceName;
  final String? errorMessage;
  final bool busy;
}

/// Phone onboarding stages.
enum PhoneOnboardingStage {
  welcome,
  scan,
  manualEntry,
  fingerprintConfirm,
  confirmCode,
  waitingApproval,
  permissions,
  connected,
  error,
}

@immutable
class PhoneOnboardingData {
  const PhoneOnboardingData({
    required this.stage,
    this.desktopName,
    this.confirmationCode,
    this.manualAddress,
    this.fingerprint,
    this.permissions = const <PermissionStepState>[],
    this.errorMessage,
    this.errorActionLabel,
    this.busy = false,
  });

  final PhoneOnboardingStage stage;
  final String? desktopName;
  final String? confirmationCode;

  /// Prefills the manual-entry field (`host:port`).
  final String? manualAddress;

  /// Short certificate fingerprint shown during manual pairing.
  final String? fingerprint;

  final List<PermissionStepState> permissions;
  final String? errorMessage;
  final String? errorActionLabel;
  final bool busy;
}

/// Android share panel status. Copy is truthful: offline saves are not
/// described as delivered (SHARE-005).
enum SharePanelStatus { saved, offlineSaved, unsupported, storageError }
