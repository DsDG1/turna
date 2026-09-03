import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/views/theme.dart';

/// A node in the multi-level deck tree.
class DeckTreeNode {
  DeckTreeNode({
    required this.name,
    required this.fullPath,
    this.deckId,
    this.cardCount = 0,
    List<DeckTreeNode>? children,
    this.isExpanded = true,
    this.archetypeLabel,
  }) : children = children ?? [];

  final String name;
  final String fullPath;
  final int? deckId;
  int cardCount;
  final List<DeckTreeNode> children;
  bool isExpanded;
  String? archetypeLabel;

  int get subtreeCardCount {
    var total = cardCount;
    for (final child in children) {
      total += child.subtreeCardCount;
    }
    return total;
  }
}

/// Builds a multi-level deck tree from flat Anki deck nodes and counts.
List<DeckTreeNode> buildDeckTree(
  List<OfficialAnkiDeckNode> decks,
  Map<int, int> cardCountByDeck, {
  Map<int, String>? archetypeLabelByDeck,
}) {
  final roots = <DeckTreeNode>[];
  final nodeMap = <String, DeckTreeNode>{};

  for (final deck in decks) {
    final parts = deck.name.split('::');
    var currentPath = '';
    DeckTreeNode? parent;

    for (var i = 0; i < parts.length; i++) {
      final segment = parts[i].trim();
      if (segment.isEmpty) continue;
      currentPath = currentPath.isEmpty ? segment : '$currentPath::$segment';
      final isLeaf = (i == parts.length - 1);

      var node = nodeMap[currentPath];
      if (node == null) {
        node = DeckTreeNode(
          name: segment,
          fullPath: currentPath,
          deckId: isLeaf ? deck.deckId : null,
          cardCount: isLeaf ? (cardCountByDeck[deck.deckId] ?? 0) : 0,
          isExpanded: true,
          archetypeLabel: isLeaf && archetypeLabelByDeck != null
              ? archetypeLabelByDeck[deck.deckId]
              : null,
        );
        nodeMap[currentPath] = node;
        if (parent != null) {
          parent.children.add(node);
        } else {
          roots.add(node);
        }
      } else if (isLeaf) {
        node.cardCount = cardCountByDeck[deck.deckId] ?? 0;
        if (archetypeLabelByDeck != null &&
            archetypeLabelByDeck[deck.deckId] != null) {
          node.archetypeLabel = archetypeLabelByDeck[deck.deckId];
        }
      }
      parent = node;
    }
  }

  return roots;
}

/// Directory tree view rendering nested Anki deck chapters with collapse/expand.
class DeckDirectoryTreeView extends StatelessWidget {
  const DeckDirectoryTreeView({
    super.key,
    required this.deckTree,
    required this.totalDecks,
    required this.onToggle,
    this.onInspectNode,
  });

  final List<DeckTreeNode> deckTree;
  final int totalDecks;
  final VoidCallback onToggle;
  final void Function(DeckTreeNode node)? onInspectNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 18,
                color: TurnaTheme.brandTeal,
              ),
              const SizedBox(width: 6),
              const Text(
                '完整章节目录',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$totalDecks 个章节节点',
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final root in deckTree)
            DeckTreeNodeWidget(
              node: root,
              depth: 0,
              onToggle: onToggle,
              onInspectNode: onInspectNode,
            ),
        ],
      ),
    );
  }
}

class DeckTreeNodeWidget extends StatelessWidget {
  const DeckTreeNodeWidget({
    super.key,
    required this.node,
    required this.depth,
    required this.onToggle,
    this.onInspectNode,
  });

  final DeckTreeNode node;
  final int depth;
  final VoidCallback onToggle;
  final void Function(DeckTreeNode node)? onInspectNode;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final count = hasChildren ? node.subtreeCardCount : node.cardCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: depth * 16.0,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            children: [
              if (hasChildren)
                GestureDetector(
                  onTap: () {
                    node.isExpanded = !node.isExpanded;
                    onToggle();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      node.isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 18,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                )
              else
                const SizedBox(width: 26),
              Icon(
                hasChildren
                    ? (node.isExpanded
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded)
                    : Icons.library_books_outlined,
                size: 16,
                color: hasChildren
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.textSecondaryColor(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        hasChildren ? FontWeight.w600 : FontWeight.w400,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
                ),
              ),
              if (node.archetypeLabel != null) ...[
                GestureDetector(
                  onTap: onInspectNode != null
                      ? () => onInspectNode!(node)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: TurnaTheme.brandTeal.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      node.archetypeLabel!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: TurnaTheme.brandTeal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                ),
                child: Text(
                  '$count 张卡片',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasChildren && node.isExpanded)
          for (final child in node.children)
            DeckTreeNodeWidget(
              node: child,
              depth: depth + 1,
              onToggle: onToggle,
              onInspectNode: onInspectNode,
            ),
      ],
    );
  }
}
