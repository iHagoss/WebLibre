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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:weblibre/features/geckoview/domain/providers/tab_state.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_layout.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_mode.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/providers/pane_controller.dart';

/// Touch-friendly 1 / 2 / 3 / 4 pane mode switcher.
///
/// Designed for Samsung Galaxy S10+ class phones:
///  - Each button reserves at least 48 logical pixels of hit area.
///  - The active mode is visually highlighted.
///  - Hidden automatically when the focused tab is in fullscreen so it never
///    overlaps fullscreen web content (e.g. video).
///
/// The switcher defaults to a small **collapsed chip** showing the current
/// pane-mode number so it does not permanently cover the underlying web
/// content. Interactions:
///  - Tap the chip -> expand into the full 1 / 2 / 3 / 4 row + settings menu.
///  - Tap the chevron in the expanded row -> collapse back to the chip.
///  - Long-press anywhere on the chip or expanded bar -> enter drag mode and
///    freely reposition the switcher over the viewport. The drag offset is
///    kept inside the surrounding parent constraints.
///  - Tap the "..." button (expanded only) -> opens a placeholder per-pane
///    options menu reserved for future settings (currently informational
///    only — no destructive options exposed yet).
class PaneModeSwitcher extends ConsumerStatefulWidget {
  /// Minimum hit area side (logical pixels) per Galaxy S10+ rule in TASK.md.
  static const double _minHitArea = 48;

  const PaneModeSwitcher({super.key});

  @override
  ConsumerState<PaneModeSwitcher> createState() => _PaneModeSwitcherState();
}

class _PaneModeSwitcherState extends ConsumerState<PaneModeSwitcher> {
  /// Whether the switcher is in compact chip mode (true) or expanded row.
  /// Starts collapsed so the switcher does not permanently cover content.
  bool _collapsed = true;

  /// Cumulative user-driven drag offset applied on top of the parent's
  /// `Positioned` anchor. `null` means the user has not moved it yet, so the
  /// switcher snaps to whatever location the parent chose.
  Offset? _dragOffset;

  /// True while a long-press-driven drag is in progress; used purely for
  /// visual feedback (elevated shadow) to signal the bar is being moved.
  bool _dragging = false;

  void _toggleCollapsed() {
    setState(() => _collapsed = !_collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = ref.watch(
      selectedTabStateProvider.select((s) => s?.isFullScreen ?? false),
    );
    if (isFullScreen) {
      return const SizedBox.shrink();
    }

    final mode = ref.watch(paneControllerProvider.select((s) => s.mode));

    final offset = _dragOffset ?? Offset.zero;

    // Transform.translate applies the long-press-drag offset on top of
    // wherever the parent Positioned has anchored us, without changing the
    // parent's stack ordering.
    return Transform.translate(
      offset: offset,
      child: _DraggableScope(
        onDragDelta: (delta) {
          setState(() {
            _dragOffset = (_dragOffset ?? Offset.zero) + delta;
          });
        },
        onDragStart: () => setState(() => _dragging = true),
        onDragEnd: () => setState(() => _dragging = false),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: _collapsed
              ? _CollapsedChip(
                  key: const ValueKey('pane-switcher-collapsed'),
                  mode: mode,
                  dragging: _dragging,
                  onTap: _toggleCollapsed,
                  minHitArea: PaneModeSwitcher._minHitArea,
                )
              : _ExpandedBar(
                  key: const ValueKey('pane-switcher-expanded'),
                  mode: mode,
                  dragging: _dragging,
                  onCollapse: _toggleCollapsed,
                  onSelectMode: (m) =>
                      ref.read(paneControllerProvider.notifier).setMode(m),
                  onLongPressMode: (m) => _onLongPressMode(context, m),
                  onOpenSettings: () => _showSettingsMenu(context),
                  minHitArea: PaneModeSwitcher._minHitArea,
                ),
        ),
      ),
    );
  }

  /// Tasks 44 + 45 — Long-press on a pane-mode button. Today only the "3"
  /// button has a secondary chooser (portrait vs landscape sub-layouts).
  /// Other modes fall through to a no-op so the UX is consistent (every
  /// button is long-pressable; only 3 currently has options).
  void _onLongPressMode(BuildContext context, PaneMode mode) {
    if (mode != PaneMode.three) return;
    _showThreePaneSubLayoutChooser(context);
  }

  void _showThreePaneSubLayoutChooser(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait =
        mediaQuery.orientation == Orientation.portrait ||
        mediaQuery.size.height >= mediaQuery.size.width;

    // Only offer the layouts that apply to the current orientation.
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) {
          final state = ref.read(paneControllerProvider);
          final notifier = ref.read(paneControllerProvider.notifier);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text(
                    isPortrait
                        ? 'Three panes — portrait layout'
                        : 'Three panes — landscape layout',
                  ),
                  subtitle: const Text('Choose how three panes are arranged.'),
                ),
                const Divider(height: 1),
                if (isPortrait) ...[
                  RadioGroup<ThreePanePortraitLayout>(
                    groupValue: state.threePortraitLayout,
                    onChanged: (v) {
                      if (v != null) {
                        notifier.setMode(PaneMode.three);
                        notifier.setThreePortraitLayout(v);
                      }
                      Navigator.of(sheetCtx).pop();
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<ThreePanePortraitLayout>(
                          secondary: Icon(Icons.view_agenda_outlined),
                          title: Text('Rows3 — top + split bottom (default)'),
                          subtitle: Text(
                            'Pane 1 spans full width on top; panes 2 and 3 share '
                            'the bottom row.',
                          ),
                          value: ThreePanePortraitLayout.topRowAndSplitBottom,
                        ),
                        RadioListTile<ThreePanePortraitLayout>(
                          secondary: Icon(Icons.view_column_outlined),
                          title: Text('Columns3 — three equal columns'),
                          subtitle: Text(
                            'Three vertical columns side-by-side. Requires '
                            'at least 240 logical-px per column.',
                          ),
                          value: ThreePanePortraitLayout.equalColumns,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  RadioGroup<ThreePaneLandscapeLayout>(
                    groupValue: state.threeLandscapeLayout,
                    onChanged: (v) {
                      if (v != null) {
                        notifier.setMode(PaneMode.three);
                        notifier.setThreeLandscapeLayout(v);
                      }
                      Navigator.of(sheetCtx).pop();
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<ThreePaneLandscapeLayout>(
                          secondary: Icon(Icons.view_column_outlined),
                          title: Text(
                            'Columns3 — left large + stacked right (default)',
                          ),
                          subtitle: Text(
                            'Pane 1 occupies the left half; panes 2 and 3 share '
                            'the stacked right column.',
                          ),
                          value: ThreePaneLandscapeLayout.leftLargeRightStacked,
                        ),
                        RadioListTile<ThreePaneLandscapeLayout>(
                          secondary: Icon(Icons.view_agenda_outlined),
                          title: Text('Rows3 — three equal rows'),
                          subtitle: Text(
                            'Three horizontal rows stacked top-to-bottom. Requires '
                            'at least 200 logical-px per row.',
                          ),
                          value: ThreePaneLandscapeLayout.equalRows,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    // Per-pane options menu placeholder. Today it only shows informational
    // entries; future iterations can add destructive/configurable actions
    // (close pane tab, duplicate pane, swap panes, …). Kept lightweight so
    // adding entries later doesn't require rewiring callers.
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Pane options'),
                subtitle: Text(
                  'Long-press the switcher to drag it. Tap to collapse/expand.',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset switcher position'),
                onTap: () {
                  setState(() => _dragOffset = null);
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A gesture wrapper that converts long-press-and-drag motion into incremental
/// `Offset` deltas. Pulled out so the switcher's main `build` stays readable
/// and so the gesture set can be reused/tested without the rest of the bar.
class _DraggableScope extends StatelessWidget {
  final ValueChanged<Offset> onDragDelta;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final Widget child;

  const _DraggableScope({
    required this.onDragDelta,
    required this.onDragStart,
    required this.onDragEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Offset? lastPosition;
    return Listener(
      // Listener so we can collect long-press pan events without conflicting
      // with the inner buttons' tap GestureDetectors.
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPressStart: (details) {
          lastPosition = details.globalPosition;
          onDragStart();
        },
        onLongPressMoveUpdate: (details) {
          final prev = lastPosition;
          lastPosition = details.globalPosition;
          if (prev != null) {
            onDragDelta(details.globalPosition - prev);
          }
        },
        onLongPressEnd: (_) {
          lastPosition = null;
          onDragEnd();
        },
        child: child,
      ),
    );
  }
}

/// Compact circular chip showing the current pane-mode number.
class _CollapsedChip extends StatelessWidget {
  final PaneMode mode;
  final bool dragging;
  final VoidCallback onTap;
  final double minHitArea;

  const _CollapsedChip({
    super.key,
    required this.mode,
    required this.dragging,
    required this.onTap,
    required this.minHitArea,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '${mode.semanticLabel}. Tap to expand pane switcher.',
      hint: 'Long-press and drag to move.',
      child: Material(
        color: scheme.surface.withValues(alpha: 0.9),
        elevation: dragging ? 8 : 3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: minHitArea,
            height: minHitArea,
            child: Center(
              child: Text(
                mode.displayLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanded row showing 1 / 2 / 3 / 4, plus a collapse chevron and "..."
/// settings menu button.
class _ExpandedBar extends StatelessWidget {
  final PaneMode mode;
  final bool dragging;
  final VoidCallback onCollapse;
  final ValueChanged<PaneMode> onSelectMode;
  final ValueChanged<PaneMode> onLongPressMode;
  final VoidCallback onOpenSettings;
  final double minHitArea;

  const _ExpandedBar({
    super.key,
    required this.mode,
    required this.dragging,
    required this.onCollapse,
    required this.onSelectMode,
    required this.onLongPressMode,
    required this.onOpenSettings,
    required this.minHitArea,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface.withValues(alpha: 0.9),
      elevation: dragging ? 8 : 3,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in PaneMode.values)
              _PaneModeButton(
                mode: value,
                selected: value == mode,
                onTap: () => onSelectMode(value),
                onLongPress: () => onLongPressMode(value),
                minHitArea: minHitArea,
              ),
            _IconActionButton(
              icon: Icons.more_horiz,
              semanticLabel: 'Pane options',
              minHitArea: minHitArea,
              onTap: onOpenSettings,
            ),
            _IconActionButton(
              icon: Icons.chevron_right,
              semanticLabel: 'Collapse pane switcher',
              minHitArea: minHitArea,
              onTap: onCollapse,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaneModeButton extends StatelessWidget {
  final PaneMode mode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double minHitArea;

  const _PaneModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.minHitArea,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background = selected ? scheme.primary : Colors.transparent;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;

    // Tasks 44 + 45 — Long-press is the secondary chooser entry point.
    // Today only `PaneMode.three` opens a sub-layout menu; other modes
    // receive the long-press signal but the handler is a no-op (kept
    // uniform so adding future long-press affordances doesn't require
    // touching this widget).
    return Semantics(
      button: true,
      selected: selected,
      label: mode.semanticLabel,
      hint: mode == PaneMode.three ? 'Long-press to choose sub-layout.' : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minHitArea,
          minHeight: minHitArea,
        ),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Center(
              child: Text(
                mode.displayLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final double minHitArea;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.minHitArea,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minHitArea,
          minHeight: minHitArea,
        ),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            onTap: onTap,
            child: Center(child: Icon(icon, color: scheme.onSurface)),
          ),
        ),
      ),
    );
  }
}
