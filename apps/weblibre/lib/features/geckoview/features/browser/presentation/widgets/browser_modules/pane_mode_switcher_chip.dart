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
import 'package:weblibre/features/geckoview/features/browser/presentation/widgets/toolbar_button.dart';

class PaneModeSwitcherChip extends ConsumerWidget {
  const PaneModeSwitcherChip({super.key});

  static const double _minHitArea = 44;

  IconData _iconFor(PaneMode mode) => switch (mode) {
    PaneMode.single => Icons.crop_square,
    PaneMode.two => Icons.view_column_outlined,
    PaneMode.three => Icons.view_quilt_outlined,
    PaneMode.four => Icons.grid_view_outlined,
  };

  IconData _threePortraitLayoutIcon(ThreePanePortraitLayout layout) =>
      switch (layout) {
        ThreePanePortraitLayout.topRowAndSplitBottom =>
          Icons.view_agenda_outlined,
        ThreePanePortraitLayout.equalColumns => Icons.view_column_outlined,
      };

  String _threePortraitLayoutTitle(ThreePanePortraitLayout layout) =>
      switch (layout) {
        ThreePanePortraitLayout.topRowAndSplitBottom =>
          'Rows3 — top + split bottom',
        ThreePanePortraitLayout.equalColumns => 'Columns3 — equal columns',
      };

  String _threePortraitLayoutSubtitle(
    ThreePanePortraitLayout layout,
  ) => switch (layout) {
    ThreePanePortraitLayout.topRowAndSplitBottom =>
      'Default portrait layout: pane 1 on top, panes 2 and 3 below.',
    ThreePanePortraitLayout.equalColumns =>
      'Three equal portrait columns, used when each pane is at least 240 px.',
  };

  IconData _threeLandscapeLayoutIcon(ThreePaneLandscapeLayout layout) =>
      switch (layout) {
        ThreePaneLandscapeLayout.leftLargeRightStacked =>
          Icons.view_column_outlined,
        ThreePaneLandscapeLayout.equalRows => Icons.view_agenda_outlined,
      };

  String _threeLandscapeLayoutTitle(ThreePaneLandscapeLayout layout) =>
      switch (layout) {
        ThreePaneLandscapeLayout.leftLargeRightStacked =>
          'Columns3 — left large + stacked right',
        ThreePaneLandscapeLayout.equalRows => 'Rows3 — equal rows',
      };

  String _threeLandscapeLayoutSubtitle(
    ThreePaneLandscapeLayout layout,
  ) => switch (layout) {
    ThreePaneLandscapeLayout.leftLargeRightStacked =>
      'Default landscape layout: pane 1 on the left, panes 2 and 3 stacked on the right.',
    ThreePaneLandscapeLayout.equalRows =>
      'Three full-width landscape rows, used when each row is at least 200 px tall.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFullScreen = ref.watch(
      selectedTabStateProvider.select((s) => s?.isFullScreen ?? false),
    );
    if (isFullScreen) {
      return const SizedBox.shrink();
    }

    final mode = ref.watch(paneControllerProvider.select((s) => s.mode));
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label:
          '${mode.semanticLabel}. Tap to change pane mode. '
          'Long-press the 3 option for current-orientation layout choices.',
      child: ToolbarButton(
        onTap: () => unawaited(_showPaneMenu(context, ref, mode)),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(5.0),
          ),
          constraints: const BoxConstraints(
            minWidth: _minHitArea,
            minHeight: 25.0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
          child: Center(
            child: Icon(
              _iconFor(mode),
              size: 18.0,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  RelativeRect? _menuPositionFor(BuildContext context) {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    if (button == null || overlay == null) {
      return null;
    }

    return RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
  }

  bool _isPortrait(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.orientation == Orientation.portrait ||
        mediaQuery.size.height >= mediaQuery.size.width;
  }

  Future<void> _showPaneMenu(
    BuildContext context,
    WidgetRef ref,
    PaneMode currentMode,
  ) async {
    final position = _menuPositionFor(context);
    if (position == null) return;

    final scheme = Theme.of(context).colorScheme;

    final selected = await showMenu<PaneMode>(
      context: context,
      position: position,
      items: [
        for (final value in PaneMode.values)
          PopupMenuItem<PaneMode>(
            value: value,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: value == PaneMode.three
                  ? () {
                      Navigator.of(context).pop();
                      unawaited(
                        _showThreePaneLayoutChooser(context, ref, position),
                      );
                    }
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(value),
                    size: 20.0,
                    color: value == currentMode
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    value.semanticLabel,
                    style: TextStyle(
                      fontWeight: value == currentMode
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: value == currentMode
                          ? scheme.primary
                          : scheme.onSurface,
                    ),
                  ),
                  if (value == PaneMode.three) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );

    if (selected != null && selected != currentMode) {
      ref.read(paneControllerProvider.notifier).setMode(selected);
    }
  }

  Future<void> _showThreePaneLayoutChooser(
    BuildContext context,
    WidgetRef ref,
    RelativeRect position,
  ) async {
    if (_isPortrait(context)) {
      await _showThreePortraitLayoutChooser(context, ref, position);
      return;
    }

    await _showThreeLandscapeLayoutChooser(context, ref, position);
  }

  Future<void> _showThreePortraitLayoutChooser(
    BuildContext context,
    WidgetRef ref,
    RelativeRect position,
  ) async {
    final state = ref.read(paneControllerProvider);
    final currentLayout = state.threePortraitLayout;
    final scheme = Theme.of(context).colorScheme;

    final selected = await showMenu<ThreePanePortraitLayout>(
      context: context,
      position: position,
      items: [
        for (final layout in ThreePanePortraitLayout.values)
          PopupMenuItem<ThreePanePortraitLayout>(
            value: layout,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _threePortraitLayoutIcon(layout),
                  size: 22,
                  color: layout == currentLayout
                      ? scheme.primary
                      : scheme.onSurface,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _threePortraitLayoutTitle(layout),
                        style: TextStyle(
                          fontWeight: layout == currentLayout
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: layout == currentLayout
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _threePortraitLayoutSubtitle(layout),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (selected == null) return;

    final notifier = ref.read(paneControllerProvider.notifier);
    notifier.setMode(PaneMode.three);
    notifier.setThreePortraitLayout(selected);
  }

  Future<void> _showThreeLandscapeLayoutChooser(
    BuildContext context,
    WidgetRef ref,
    RelativeRect position,
  ) async {
    final state = ref.read(paneControllerProvider);
    final currentLayout = state.threeLandscapeLayout;
    final scheme = Theme.of(context).colorScheme;

    final selected = await showMenu<ThreePaneLandscapeLayout>(
      context: context,
      position: position,
      items: [
        for (final layout in ThreePaneLandscapeLayout.values)
          PopupMenuItem<ThreePaneLandscapeLayout>(
            value: layout,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _threeLandscapeLayoutIcon(layout),
                  size: 22,
                  color: layout == currentLayout
                      ? scheme.primary
                      : scheme.onSurface,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _threeLandscapeLayoutTitle(layout),
                        style: TextStyle(
                          fontWeight: layout == currentLayout
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: layout == currentLayout
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _threeLandscapeLayoutSubtitle(layout),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (selected == null) return;

    final notifier = ref.read(paneControllerProvider.notifier);
    notifier.setMode(PaneMode.three);
    notifier.setThreeLandscapeLayout(selected);
  }
}
