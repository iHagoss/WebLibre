/*
 * Copyright (c) 2024-2026 Fabian Freund.
 *
 * This file is part of WebLibre
 * (see https://weblibre.eu).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_layout.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_mode.dart';

/// Immutable representation of the split-pane state on the Dart side.
///
/// Invariants:
///  - [paneTabIds] always has exactly 4 entries after startup seeding so switching
///    pane mode never destroys assignments (hidden assignments are preserved while
///    the user uses a smaller mode and can be re-shown when expanding back).
///  - [focusedPaneIndex] is clamped to the valid range `[0, mode.paneCount - 1]`.
///  - Divider fractions ([splitH], [splitV], [splitSecondary]) are clamped into
///    `[_minSplit, 1 - _minSplit]` so neither side of a divider can collapse below
///    a usable touch target (Galaxy S10+ thumb-friendly minimum).
///
/// Cross-pane isolation note:
///  - Each entry in [paneTabIds] is the id of a tab whose isolation context was
///    decided at tab creation time (see `PaneController.ensureStartupPanesSeeded`
///    which uses `TabMode.newIsolated()` for every seeded pane). Reassigning an
///    existing tab to another pane slot via the controller does NOT mutate the
///    tab's persisted isolation/contextual identity; it only changes which
///    slot displays it. Each pane slot is therefore "distinctly isolated" only
///    insofar as the tab it currently holds was created isolated. Future UI
///    that moves arbitrary tabs into panes should preserve this contract by
///    creating a fresh isolated tab for the slot rather than retro-fitting
///    isolation onto a shared tab.
class PaneState {
  static const int paneSlotCount = 4;

  /// Lower clamp for divider fractions so a pane cannot shrink past a
  /// thumb-friendly minimum (~15% of the available axis).
  static const double minSplit = 0.15;
  static const double _minSplit = minSplit;

  final PaneMode mode;

  /// Tab ids assigned to each of the four pane slots. Slots beyond
  /// [PaneMode.paneCount] are hidden but preserved across mode changes.
  /// A null entry means the slot is unassigned (no seeded tab yet).
  final List<String?> paneTabIds;

  /// Index (0-based) of the currently focused pane within the visible panes.
  final int focusedPaneIndex;

  /// Fractional position (0..1) of the primary horizontal divider — the one
  /// that splits the layout into left vs right columns.
  /// Used by: two-pane landscape, three-pane landscape (outer), four-pane
  /// (top row inner) layouts.
  final double splitH;

  /// Fractional position (0..1) of the primary vertical divider — the one
  /// that splits the layout into top vs bottom rows.
  /// Used by: two-pane portrait, three-pane portrait (outer), four-pane
  /// (outer) layouts.
  final double splitV;

  /// Fractional position (0..1) of the secondary divider that appears inside
  /// the sub-row/sub-column of three- and four-pane layouts.
  /// Used by: three-pane portrait (bottom row split), three-pane landscape
  /// (right column split), four-pane (bottom row split).
  final double splitSecondary;

  /// Task 44 — Sub-layout used when [mode] is [PaneMode.three] and the
  /// device is in portrait orientation. Default preserves the original
  /// Task 17 layout (top full-width + bottom two half-width).
  final ThreePanePortraitLayout threePortraitLayout;

  /// Task 45 — Sub-layout used when [mode] is [PaneMode.three] and the
  /// device is in landscape orientation. Default preserves the original
  /// Task 17 layout (large left + two stacked right).
  final ThreePaneLandscapeLayout threeLandscapeLayout;

  PaneState({
    required this.mode,
    required List<String?> paneTabIds,
    required int focusedPaneIndex,
    double splitH = 0.5,
    double splitV = 0.5,
    double splitSecondary = 0.5,
    this.threePortraitLayout = ThreePanePortraitLayout.topRowAndSplitBottom,
    this.threeLandscapeLayout = ThreePaneLandscapeLayout.leftLargeRightStacked,
  }) : assert(
         paneTabIds.length == paneSlotCount,
         'paneTabIds must always have exactly $paneSlotCount entries',
       ),
       paneTabIds = List.unmodifiable(paneTabIds),
       focusedPaneIndex = _clampIndex(focusedPaneIndex, mode.paneCount),
       splitH = _clampFraction(splitH),
       splitV = _clampFraction(splitV),
       splitSecondary = _clampFraction(splitSecondary);

  /// Initial state: single pane mode, no tab assignments yet, focused on slot 0.
  factory PaneState.initial() => PaneState(
    mode: PaneMode.single,
    paneTabIds: List<String?>.filled(paneSlotCount, null),
    focusedPaneIndex: 0,
  );

  static int _clampIndex(int index, int paneCount) {
    if (paneCount <= 0) return 0;
    if (index < 0) return 0;
    if (index >= paneCount) return paneCount - 1;
    return index;
  }

  static double _clampFraction(double value) {
    if (value.isNaN) return 0.5;
    const low = _minSplit;
    const high = 1 - _minSplit;
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }

  /// Number of currently visible panes.
  int get visiblePaneCount => mode.paneCount;

  /// Tab ids for the currently visible panes only (length == [visiblePaneCount]).
  List<String?> get visibleTabIds =>
      List.unmodifiable(paneTabIds.take(visiblePaneCount));

  /// Tab id of the currently focused visible pane, if any.
  String? get focusedTabId {
    if (focusedPaneIndex < 0 || focusedPaneIndex >= visiblePaneCount) {
      return null;
    }
    return paneTabIds[focusedPaneIndex];
  }

  PaneState copyWith({
    PaneMode? mode,
    List<String?>? paneTabIds,
    int? focusedPaneIndex,
    double? splitH,
    double? splitV,
    double? splitSecondary,
    ThreePanePortraitLayout? threePortraitLayout,
    ThreePaneLandscapeLayout? threeLandscapeLayout,
  }) {
    return PaneState(
      mode: mode ?? this.mode,
      paneTabIds: paneTabIds ?? this.paneTabIds,
      focusedPaneIndex: focusedPaneIndex ?? this.focusedPaneIndex,
      splitH: splitH ?? this.splitH,
      splitV: splitV ?? this.splitV,
      splitSecondary: splitSecondary ?? this.splitSecondary,
      threePortraitLayout: threePortraitLayout ?? this.threePortraitLayout,
      threeLandscapeLayout: threeLandscapeLayout ?? this.threeLandscapeLayout,
    );
  }

  /// Returns a new state with [tabId] assigned to pane [index].
  PaneState withTabAt(int index, String? tabId) {
    if (index < 0 || index >= paneSlotCount) return this;
    final updated = List<String?>.from(paneTabIds);
    updated[index] = tabId;
    return copyWith(paneTabIds: updated);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PaneState) return false;
    if (other.mode != mode) return false;
    if (other.focusedPaneIndex != focusedPaneIndex) return false;
    if (other.splitH != splitH) return false;
    if (other.splitV != splitV) return false;
    if (other.splitSecondary != splitSecondary) return false;
    if (other.threePortraitLayout != threePortraitLayout) return false;
    if (other.threeLandscapeLayout != threeLandscapeLayout) return false;
    if (other.paneTabIds.length != paneTabIds.length) return false;
    for (var i = 0; i < paneTabIds.length; i++) {
      if (other.paneTabIds[i] != paneTabIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    focusedPaneIndex,
    splitH,
    splitV,
    splitSecondary,
    threePortraitLayout,
    threeLandscapeLayout,
    Object.hashAll(paneTabIds),
  );

  @override
  String toString() =>
      'PaneState(mode: $mode, focusedPaneIndex: $focusedPaneIndex, '
      'splitH: $splitH, splitV: $splitV, splitSecondary: $splitSecondary, '
      'threePortraitLayout: $threePortraitLayout, '
      'threeLandscapeLayout: $threeLandscapeLayout, '
      'paneTabIds: $paneTabIds)';
}
