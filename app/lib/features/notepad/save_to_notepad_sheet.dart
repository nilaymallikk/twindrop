import 'package:flutter/material.dart';
import 'package:twindrop_core/models/category.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/category_nav.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/states.dart';
import '../../widgets/td_icons.dart';
import '../models.dart';
import 'category_dialog.dart';

/// Sheet that turns a chat message or link into a new note (NOTE-004).
///
/// Returns null when dismissed. The last used category is preselected; a new
/// category can be created inline, and the host's error message is shown in the
/// name dialog instead of being dropped.
Future<SaveToNotepadResult?> showSaveToNotepadSheet(
  BuildContext context, {
  required List<Category> categories,
  String? initialCategoryId,
  Future<String?> Function(String name)? onCreateCategory,
}) {
  return showTdSheet<SaveToNotepadResult>(
    context,
    title: 'Save to Notepad',
    builder: (sheetContext) => _SaveToNotepadForm(
      categories: categories,
      initialCategoryId: initialCategoryId,
      onCreateCategory: onCreateCategory,
    ),
  );
}

class _SaveToNotepadForm extends StatefulWidget {
  const _SaveToNotepadForm({
    required this.categories,
    this.initialCategoryId,
    this.onCreateCategory,
  });

  final List<Category> categories;
  final String? initialCategoryId;
  final Future<String?> Function(String name)? onCreateCategory;

  @override
  State<_SaveToNotepadForm> createState() => _SaveToNotepadFormState();
}

class _SaveToNotepadFormState extends State<_SaveToNotepadForm> {
  final TextEditingController _titleController = TextEditingController();
  late String _categoryId = _initialCategoryId();
  String? _notice;

  String _initialCategoryId() {
    final live = _liveCategories;
    final requested = widget.initialCategoryId;
    if (requested != null && live.any((c) => c.id == requested)) {
      return requested;
    }
    final inbox = live.where((c) => c.isInbox || c.id == Category.inboxId);
    if (inbox.isNotEmpty) return inbox.first.id;
    return live.isEmpty ? Category.inboxId : live.first.id;
  }

  List<Category> get _liveCategories {
    final live = widget.categories.where((c) => !c.deleted).toList();
    live.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return live;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _createCategory() async {
    final onCreate = widget.onCreateCategory;
    if (onCreate == null) return;
    final created = await showCategoryNameDialog(
      context,
      title: 'New category',
      confirmLabel: 'Create',
      onSubmit: onCreate,
    );
    if (!mounted || created == null) return;
    setState(() {
      _notice =
          'Added “$created”. It appears in the list the next time you '
          'save.';
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    Navigator.of(context).pop(
      SaveToNotepadResult(
        categoryId: _categoryId,
        title: title.isEmpty ? null : title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final categories = _liveCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _titleController,
          style: context.tdBody,
          cursorColor: tokens.accent,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Title (optional)'),
        ),
        const SizedBox(height: TdSpace.s16),
        const TdSectionLabel('Category'),
        TdCategoryTabs(
          items: <TdCategoryItem>[
            for (final category in categories)
              TdCategoryItem(
                id: category.id,
                name: category.name,
                isInbox: category.isInbox || category.id == Category.inboxId,
              ),
          ],
          selectedId: _categoryId,
          onSelected: (id) => setState(() => _categoryId = id),
        ),
        if (widget.onCreateCategory != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: TdSpace.s8),
              child: TdInlineAction(
                label: 'New category',
                onPressed: _createCategory,
              ),
            ),
          ),
        if (_notice != null) ...<Widget>[
          const SizedBox(height: TdSpace.s8),
          Text(_notice!, style: type.secondary.copyWith(color: tokens.muted)),
        ],
        const SizedBox(height: TdSpace.s20),
        Row(
          children: <Widget>[
            Expanded(
              child: TdButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: TdSpace.s8),
            Expanded(
              child: TdButton(
                label: 'Save',
                variant: TdButtonVariant.primary,
                icon: TdIcons.check,
                onPressed: categories.isEmpty ? null : _save,
                disabledReason: categories.isEmpty
                    ? 'Create a category before saving.'
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
