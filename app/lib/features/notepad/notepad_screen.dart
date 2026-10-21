import 'package:flutter/material.dart';
import 'package:twindrop_core/models/category.dart';
import 'package:twindrop_core/models/item.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/category_nav.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/note_card.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/search_field.dart';
import '../../widgets/states.dart';
import '../../widgets/td_icons.dart';
import '../../widgets/undo_bar.dart';
import '../format.dart';
import '../models.dart';
import 'category_dialog.dart';

/// The notepad: search, categories, and note cards.
///
/// Phone layout puts categories in tabs above the list; desktop (or any window
/// at least [TdBreakpoint.phoneMax] wide when [showSidebar] is set) uses the
/// category sidebar. Sorting is pinned-first, then newest (docs/13 §6).
class NotepadScreen extends StatefulWidget {
  const NotepadScreen({
    super.key,
    required this.categories,
    required this.notes,
    required this.selectedCategoryId,
    this.categoryNames = const <String, String>{},
    this.searchQuery = '',
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onCategorySelected,
    this.onSearchChanged,
    this.onCreateNote,
    this.onOpenNote,
    this.onTogglePin,
    this.onDeleteNote,
    this.categoryActions,
    this.onOpenLink,
    this.showSidebar = false,
    this.undo,
  });

  final List<Category> categories;
  final List<Item> notes;
  final String selectedCategoryId;
  final Map<String, String> categoryNames;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onCategorySelected;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onCreateNote;
  final ValueChanged<Item>? onOpenNote;
  final ValueChanged<Item>? onTogglePin;
  final ValueChanged<Item>? onDeleteNote;
  final CategoryActions? categoryActions;
  final ValueChanged<String>? onOpenLink;

  /// Desktop: render the category sidebar. Ignored when the window is narrow.
  final bool showSidebar;

  /// Non-null while a delete can still be undone.
  final NotepadUndo? undo;

  @override
  State<NotepadScreen> createState() => _NotepadScreenState();
}

class _NotepadScreenState extends State<NotepadScreen> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.searchQuery,
  );

  @override
  void didUpdateWidget(NotepadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: widget.searchQuery,
        selection: TextSelection.collapsed(offset: widget.searchQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Category> get _categories {
    final live = widget.categories.where((c) => !c.deleted).toList();
    live.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return live;
  }

  List<Item> get _sortedNotes {
    final visible = widget.notes.where((n) => !n.deleted).toList();
    visible.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return visible;
  }

  List<TdCategoryItem> get _navItems {
    final counts = <String, int>{};
    for (final note in _sortedNotes) {
      final id = note.categoryId;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return <TdCategoryItem>[
      for (final category in _categories)
        TdCategoryItem(
          id: category.id,
          name: category.name,
          count: counts[category.id] ?? 0,
          isInbox: category.isInbox || category.id == Category.inboxId,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return ColoredBox(
      color: tokens.bg,
      child: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(context),
              Expanded(child: _content()),
            ],
          ),
          if (widget.undo != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TdUndoBar(
                message: widget.undo!.message,
                actionLabel: widget.undo!.actionLabel,
                onAction: widget.undo!.onUndo,
                onDismissed: widget.undo!.onDismissed,
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final noteCount = _sortedNotes.length;
    return TdScreenHeader(
      title: 'Notepad',
      subtitle: Text(
        noteCount == 1 ? '1 note' : '$noteCount notes',
        style: context.tdType.meta.copyWith(color: context.td.muted),
      ),
      actions: <Widget>[
        if (widget.onCreateNote != null)
          TdButton(
            label: 'New',
            icon: TdIcons.plus,
            variant: TdButtonVariant.secondary,
            onPressed: widget.onCreateNote,
          ),
      ],
    );
  }

  Widget _content() {
    if (widget.errorMessage != null) {
      return TdErrorState(
        message: widget.errorMessage!,
        onAction: widget.onRetry,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            widget.showSidebar && constraints.maxWidth >= TdBreakpoint.phoneMax;
        if (!wide) return _listBody(showTabs: true);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: TdCategorySidebar(
                items: _navItems,
                selectedId: widget.selectedCategoryId,
                onSelected: (id) => widget.onCategorySelected?.call(id),
                onReorder: widget.categoryActions?.onReorder,
                onRename: widget.categoryActions?.onRename == null
                    ? null
                    : _renameCategory,
                onDelete: widget.categoryActions?.onDelete == null
                    ? null
                    : _deleteCategory,
                onCreate: widget.categoryActions?.canCreate == true
                    ? _createCategory
                    : null,
              ),
            ),
            Expanded(child: _listBody(showTabs: false)),
          ],
        );
      },
    );
  }

  Widget _listBody({required bool showTabs}) {
    final notes = _sortedNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.onSearchChanged != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TdSpace.s16,
              TdSpace.s12,
              TdSpace.s16,
              TdSpace.s8,
            ),
            child: TdSearchField(
              controller: _searchController,
              onChanged: widget.onSearchChanged,
            ),
          ),
        if (showTabs && widget.onCategorySelected != null)
          TdCategoryTabs(
            items: _navItems,
            selectedId: widget.selectedCategoryId,
            onSelected: (id) => widget.onCategorySelected?.call(id),
            onCreate: widget.categoryActions?.canCreate == true
                ? _createCategory
                : null,
          ),
        Expanded(
          child: widget.isLoading
              ? const TdLoadingState(label: 'Loading notes', lines: 4)
              : notes.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: TdEmptyState(
                    message: widget.searchQuery.trim().isEmpty
                        ? 'No notes yet. Notes you create or share '
                              'appear here.'
                        : 'No notes match your search.',
                    actionLabel: widget.onCreateNote == null
                        ? null
                        : 'New note',
                    onAction: widget.onCreateNote,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(TdSpace.s16),
                  itemCount: notes.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: TdSpace.s8),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return TdNoteCard(
                      key: ValueKey<String>('note-${note.id}'),
                      title: note.title,
                      body: note.text,
                      url: note.url,
                      pinned: note.pinned,
                      conflict: note.isConflictCopy,
                      metaLabel: _metaLabel(note),
                      onTap: widget.onOpenNote == null
                          ? null
                          : () => widget.onOpenNote!(note),
                      onLongPress: _hasNoteMenu
                          ? () => _showNoteMenu(note)
                          : null,
                      onOpenLink: note.url == null || widget.onOpenLink == null
                          ? null
                          : () => widget.onOpenLink!(note.url!),
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool get _hasNoteMenu =>
      widget.onTogglePin != null || widget.onDeleteNote != null;

  String _metaLabel(Item note) {
    String? categoryName;
    for (final category in _categories) {
      if (category.id == note.categoryId) {
        categoryName = category.name;
        break;
      }
    }
    final category = widget.categoryNames[note.categoryId] ?? categoryName;
    return <String>[
      if (category != null && category.isNotEmpty) category,
      note.originName,
      tdRelativeLabel(note.createdAt),
    ].join(' · ');
  }

  Future<void> _showNoteMenu(Item note) async {
    final action = await showTdActionSheet<String>(
      context,
      title: note.title?.trim().isNotEmpty == true
          ? note.title!.trim()
          : 'Note',
      items: <TdMenuItem<String>>[
        if (widget.onTogglePin != null)
          TdMenuItem<String>(
            label: note.pinned ? 'Unpin' : 'Pin',
            result: 'pin',
            icon: TdIcons.pin,
          ),
        if (widget.onDeleteNote != null)
          const TdMenuItem<String>(
            label: 'Delete',
            result: 'delete',
            icon: TdIcons.trash,
            destructive: true,
          ),
      ],
    );
    if (!mounted) return;
    if (action == 'pin') widget.onTogglePin?.call(note);
    if (action == 'delete') widget.onDeleteNote?.call(note);
  }

  Future<void> _createCategory() async {
    final actions = widget.categoryActions;
    final onCreate = actions?.onCreate;
    if (onCreate == null) return;
    await showCategoryNameDialog(
      context,
      title: 'New category',
      confirmLabel: 'Create',
      onSubmit: onCreate,
    );
  }

  Future<void> _renameCategory(TdCategoryItem item) async {
    final onRename = widget.categoryActions?.onRename;
    if (onRename == null) return;
    await showCategoryNameDialog(
      context,
      title: 'Rename category',
      initialName: item.name,
      onSubmit: (name) => onRename(item.id, name),
    );
  }

  Future<void> _deleteCategory(TdCategoryItem item) async {
    final onDelete = widget.categoryActions?.onDelete;
    if (onDelete == null) return;
    final confirmed = await showTdConfirmDialog(
      context,
      title: 'Delete ${item.name}?',
      message: 'Notes in this category move to Inbox. Nothing is deleted.',
      confirmLabel: 'Delete category',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final deleted = await onDelete(item.id);
    if (!mounted || deleted) return;
    await showTdDialog<void>(
      context,
      title: 'Category not deleted',
      content: const Text('Inbox is fixed and cannot be renamed or deleted.'),
      actions: const <TdDialogAction<void>>[
        TdDialogAction(
          label: 'OK',
          result: null,
          variant: TdButtonVariant.primary,
        ),
      ],
    );
  }
}
