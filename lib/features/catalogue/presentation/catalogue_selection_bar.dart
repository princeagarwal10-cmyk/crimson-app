import 'package:flutter/material.dart';

class CatalogueSelectionBar extends StatelessWidget {
  const CatalogueSelectionBar({
    super.key,
    required this.selectedCount,
    required this.visibleCount,
    required this.busy,
    required this.onSelectAll,
    required this.onClear,
    required this.onExportImage,
    required this.onExportPdf,
    this.onExportStickers,
    this.onMakeLive,
    this.onMakeHidden,
    this.compact = false,
  });

  final int selectedCount;
  final int visibleCount;
  final bool busy;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onExportImage;
  final VoidCallback onExportPdf;
  final VoidCallback? onExportStickers;
  final VoidCallback? onMakeLive;
  final VoidCallback? onMakeHidden;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const crimson = Color(0xFFC8102E);
    const border = Color(0xFFE5E7EB);
    final hasSelection = selectedCount > 0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 9,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hasSelection ? crimson : border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = SizedBox(
            width: compact ? 500 : constraints.maxWidth,
            child: Row(
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                ] else
                  const Icon(Icons.library_add_check_rounded,
                      color: crimson, size: 20),
                if (!busy) const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    hasSelection
                        ? '$selectedCount products selected'
                        : '$visibleCount products available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onSelectAll,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(compact ? 'All' : 'Select all'),
                ),
                if (hasSelection) ...[
                  TextButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Clear'),
                  ),
                  if (onMakeLive != null || onMakeHidden != null)
                    PopupMenuButton<_CatalogueVisibilityAction>(
                      enabled: !busy,
                      tooltip: 'Change visibility of selected products',
                      onSelected: (action) {
                        switch (action) {
                          case _CatalogueVisibilityAction.makeLive:
                            onMakeLive?.call();
                          case _CatalogueVisibilityAction.makeHidden:
                            onMakeHidden?.call();
                        }
                      },
                      itemBuilder: (context) => [
                        if (onMakeLive != null)
                          const PopupMenuItem(
                            value: _CatalogueVisibilityAction.makeLive,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.visibility_rounded),
                              title: Text('Make selected live'),
                            ),
                          ),
                        if (onMakeHidden != null)
                          const PopupMenuItem(
                            value: _CatalogueVisibilityAction.makeHidden,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.visibility_off_rounded),
                              title: Text('Hide selected products'),
                            ),
                          ),
                      ],
                      child: compact
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.visibility_outlined),
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_outlined, size: 18),
                                  SizedBox(width: 6),
                                  Text('Visibility'),
                                ],
                              ),
                            ),
                    ),
                  IconButton(
                    tooltip: 'Export selected as catalogue images',
                    onPressed: busy ? null : onExportImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  if (onExportStickers != null)
                    IconButton(
                      tooltip: 'Export selected as 60 x 40 stickers',
                      onPressed: busy ? null : onExportStickers,
                      icon: const Icon(Icons.sell_outlined),
                    ),
                  FilledButton.icon(
                    onPressed: busy ? null : onExportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ],
              ],
            ),
          );
          if (!compact) return content;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        },
      ),
    );
  }
}

enum _CatalogueVisibilityAction { makeLive, makeHidden }
