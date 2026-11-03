import 'package:flutter/material.dart';

/// A label + value pair for a [StatTiles] cell.
typedef StatTile = ({String label, String value});

/// A row of headline stat cards (label under a prominent value), reused by the
/// per-category detail screens.
class StatTiles extends StatelessWidget {
  /// Creates a row of [tiles].
  const new({required this.tiles, super.key});

  /// The cells to render, left-to-right.
  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final tile in tiles)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    Text(tile.value, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      tile.label,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
