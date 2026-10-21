import 'package:flutter/material.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'dialogs.dart';
import 'pressable.dart';
import 'primitives.dart';
import 'td_icons.dart';

/// A category as the navigation widgets see it (counts are display-only).
@immutable
class TdCategoryItem {
  const TdCategoryItem({
    required this.id,
    required this.name,
    this.count = 0,
    this.isInbox = false,
  });

  final String id;
  final String name;
  final int count;
  final bool isInbox;
}

/// Phone category navigation: horizontal text tabs with a 2 px `paper`
/// underline on the selected tab. No chips, no icons (docs/13 §6).
class TdCategoryTabs extends StatelessWidget {
  const TdCategoryTabs({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.onCreate,
  });

  final List<TdCategoryItem> items;
  final String selectedId;
  final ValueChanged<String> onSelected;

  /// Optional trailing text action to create a category.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TdSpace.s8),
        child: Row(
          children: <Widget>[
            for (final item in items)
              TdPressable(
                onPressed: () => onSelected(item.id),
                semanticLabel: item.name,
                semanticButton: false,
                builder: (context, state) {
                  final selected = item.id == selectedId;
                  final color = selected
                      ? tokens.text
                      : state.isActive
                      ? tokens.textSecondary
                      : tokens.muted;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(
                      TdSpace.s12,
                      TdSpace.s12,
                      TdSpace.s12,
                      0,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected
                              ? tokens.paper
                              : TdPalette.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      item.name,
                      style: type.label.copyWith(color: color),
                      maxLines: 1,
                    ),
                  );
                },
              ),
            if (onCreate != null)
              TdPressable(
                onPressed: onCreate,
                semanticLabel: 'New category',
                builder: (context, state) {
                  return Container(
                    padding: const EdgeInsets.fromLTRB(
                      TdSpace.s12,
                      TdSpace.s12,
                      TdSpace.s12,
                      0,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: TdPalette.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'New',
                      style: type.label.copyWith(
                        color: state.isActive ? tokens.text : tokens.accent,
                      ),
                      maxLines: 1,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Desktop category sidebar: rows with a mono count, `raised` selected row,
/// drag reorder, right-click rename/delete, and a "+ New" row. Inbox is fixed
/// and offers no rename/delete (NOTE-002).
class TdCategorySidebar extends StatelessWidget {
  const TdCategorySidebar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.onReorder,
    this.onRename,
    this.onDelete,
    this.onCreate,
  });

  final List<TdCategoryItem> items;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final void Function(int from, int to)? onReorder;
  final ValueChanged<TdCategoryItem>? onRename;
  final ValueChanged<TdCategoryItem>? onDelete;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: tokens.hairline, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: TdSpace.s8),
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) {
                if (items[oldIndex].isInbox) return;
                final target = newIndex == 0 ? 1 : newIndex;
                onReorder?.call(oldIndex, target);
              },
              itemBuilder: (context, index) {
                final item = items[index];
                return _SidebarRow(
                  key: ValueKey<String>(item.id),
                  item: item,
                  index: index,
                  selected: item.id == selectedId,
                  onSelected: onSelected,
                  onRename: onRename,
                  onDelete: onDelete,
                );
              },
            ),
          ),
          const TdHairline(),
          if (onCreate != null)
            _NewCategoryRow(onCreate: onCreate!)
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    super.key,
    required this.item,
    required this.index,
    required this.selected,
    required this.onSelected,
    required this.onRename,
    required this.onDelete,
  });

  final TdCategoryItem item;
  final int index;
  final bool selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<TdCategoryItem>? onRename;
  final ValueChanged<TdCategoryItem>? onDelete;

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final chosen = await showTdMenu<String>(
      context,
      globalPosition: position,
      items: <TdMenuItem<String>>[
        const TdMenuItem<String>(label: 'Rename', result: 'rename'),
        const TdMenuItem<String>(label: 'Delete category', result: 'delete'),
      ],
    );
    if (chosen == 'rename') onRename?.call(item);
    if (chosen == 'delete') onDelete?.call(item);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final row = TdPressable(
      onPressed: () => onSelected(item.id),
      semanticLabel: '${item.name}, ${item.count} notes',
      builder: (context, state) {
        final active = selected || state.hovered;
        return Container(
          constraints: const BoxConstraints(minHeight: 36),
          color: active ? tokens.raised : tokens.bg,
          padding: const EdgeInsets.symmetric(horizontal: TdSpace.s8),
          child: Row(
            children: <Widget>[
              if (!item.isInbox && onRename != null)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: TdSpace.s4),
                    child: TdIcon(
                      TdIcons.grip,
                      size: TdIconSizes.sm,
                      color: tokens.muted,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  item.name,
                  style: type.label.copyWith(
                    color: selected ? tokens.text : tokens.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: TdSpace.s8),
              Text(
                '${item.count}',
                style: type.meta.copyWith(color: tokens.muted),
                maxLines: 1,
              ),
            ],
          ),
        );
      },
    );

    return GestureDetector(
      onSecondaryTapUp: item.isInbox || onRename == null
          ? null
          : (details) => _showContextMenu(context, details.globalPosition),
      child: row,
    );
  }
}

class _NewCategoryRow extends StatelessWidget {
  const _NewCategoryRow({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hairline, width: 1)),
      ),
      constraints: const BoxConstraints(minHeight: 36),
      child: TdPressable(
        onPressed: onCreate,
        semanticLabel: 'New category',
        builder: (context, state) => Container(
          color: state.isActive ? tokens.raised : tokens.bg,
          padding: const EdgeInsets.symmetric(horizontal: TdSpace.s8),
          child: Row(
            children: <Widget>[
              TdIcon(TdIcons.plus, size: TdIconSizes.sm, color: tokens.muted),
              const SizedBox(width: TdSpace.s8),
              Text(
                'New',
                style: type.label.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
