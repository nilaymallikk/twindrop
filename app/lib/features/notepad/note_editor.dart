import 'package:flutter/material.dart';
import 'package:twindrop_core/models/category.dart';
import 'package:twindrop_core/models/item.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/category_nav.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/states.dart';
import '../../widgets/td_icons.dart';
import '../models.dart';

/// Create or edit a note: title, text, category.
///
/// Save stays disabled until there is a title or text, so an empty note can
/// never be written; the reason is shown next to the button (AGENTS rule 7).
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.categories,
    this.note,
    this.initialCategoryId,
    required this.onSave,
    this.onCancel,
    this.onDelete,
  });

  final List<Category> categories;

  /// Null when creating a note.
  final Item? note;
  final String? initialCategoryId;
  final void Function(NoteDraft draft) onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _textController =
      TextEditingController(text: widget.note?.text ?? '');
  late String _categoryId = _initialCategoryId();

  String _initialCategoryId() {
    final requested =
        widget.note?.categoryId ?? widget.initialCategoryId;
    final live = _categories;
    if (requested != null && live.any((c) => c.id == requested)) {
      return requested;
    }
    final inbox = live.where((c) => c.isInbox || c.id == Category.inboxId);
    if (inbox.isNotEmpty) return inbox.first.id;
    return live.isEmpty ? Category.inboxId : live.first.id;
  }

  List<Category> get _categories {
    final live = widget.categories.where((c) => !c.deleted).toList();
    live.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return live;
  }

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onChanged);
    _textController.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.removeListener(_onChanged);
    _textController.removeListener(_onChanged);
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty ||
      _textController.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    widget.onSave(
      NoteDraft(
        title: _titleController.text.trim(),
        text: _textController.text.trim(),
        categoryId: _categoryId,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final confirmed = await showTdConfirmDialog(
      context,
      title: 'Delete this note?',
      message: 'It is removed on both devices. You can undo for 5 seconds.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return ColoredBox(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TdScreenHeader(
            title: widget.note == null ? 'New note' : 'Edit note',
            leading: widget.onCancel == null
                ? null
                : TdIconButton(
                    icon: TdIcons.arrowLeft,
                    label: 'Cancel',
                    tooltip: 'Cancel',
                    onPressed: widget.onCancel,
                  ),
            actions: <Widget>[
              if (widget.note != null && widget.onDelete != null)
                TdIconButton(
                  icon: TdIcons.trash,
                  label: 'Delete note',
                  tooltip: 'Delete note',
                  color: tokens.error,
                  onPressed: _confirmDelete,
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(TdSpace.s16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        controller: _titleController,
                        style: type.cardTitle,
                        cursorColor: tokens.accent,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'Title (optional)',
                        ),
                      ),
                      const SizedBox(height: TdSpace.s12),
                      TextField(
                        controller: _textController,
                        style: context.tdBody,
                        cursorColor: tokens.accent,
                        minLines: 6,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          hintText: 'Write a note',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: TdSpace.s20),
                      const TdSectionLabel('Category'),
                      if (_categories.isEmpty)
                        const TdNotice(
                          message: 'No categories yet. The note will go to '
                              'Inbox.',
                          tone: TdNoticeTone.neutral,
                        )
                      else
                        TdCategoryTabs(
                          items: <TdCategoryItem>[
                            for (final category in _categories)
                              TdCategoryItem(
                                id: category.id,
                                name: category.name,
                                isInbox: category.isInbox ||
                                    category.id == Category.inboxId,
                              ),
                          ],
                          selectedId: _categoryId,
                          onSelected: (id) =>
                              setState(() => _categoryId = id),
                        ),
                      const SizedBox(height: TdSpace.s24),
                      TdButton(
                        label: widget.note == null ? 'Create note' : 'Save',
                        variant: TdButtonVariant.primary,
                        icon: TdIcons.check,
                        expand: true,
                        onPressed: _canSave ? _save : null,
                        disabledReason:
                            'Add a title or some text to save this note.',
                      ),
                      if (!_canSave) ...<Widget>[
                        const SizedBox(height: TdSpace.s8),
                        Text(
                          'Add a title or some text to save this note.',
                          style: type.meta.copyWith(color: tokens.muted),
                        ),
                      ],
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
}
