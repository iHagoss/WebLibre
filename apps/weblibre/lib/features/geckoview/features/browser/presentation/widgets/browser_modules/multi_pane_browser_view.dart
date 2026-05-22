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
import 'package:flutter/material.dart';
import 'package:flutter_mozilla_components/flutter_mozilla_components.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_layout.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_mode.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_state.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/providers/pane_controller.dart';

class MultiPaneBrowserView extends ConsumerWidget {
  static const double _paneGutter = 1.0;

  final PaneState? paneState;
  final ValueChanged<int>? onFocusPane;
  final WidgetBuilder? focusedPaneOverlayBuilder;

  const MultiPaneBrowserView({
    super.key,
    this.paneState,
    this.onFocusPane,
    this.focusedPaneOverlayBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaneState paneState =
        this.paneState ?? ref.watch(paneControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxHeight >= constraints.maxWidth;
        return _buildLayout(context, ref, paneState, isPortrait);
      },
    );
  }

  Widget _buildLayout(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
    bool isPortrait,
  ) {
    switch (state.mode) {
      case PaneMode.single:
        return _paneAt(context, ref, state, 0);
      case PaneMode.two:
        return _twoPaneLayout(context, ref, state, isPortrait);
      case PaneMode.three:
        return _threePaneLayout(context, ref, state, isPortrait);
      case PaneMode.four:
        return _fourPaneLayout(context, ref, state);
    }
  }

  Widget _twoPaneLayout(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
    bool isPortrait,
  ) {
    return _SplitContainer(
      axis: isPortrait ? Axis.vertical : Axis.horizontal,
      fraction: isPortrait ? state.splitV : state.splitH,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(isPortrait ? PaneSplit.vertical : PaneSplit.horizontal, f),
      first: _paneAt(context, ref, state, 0),
      second: _paneAt(context, ref, state, 1),
    );
  }

  Widget _threePaneLayout(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
    bool isPortrait,
  ) {
    if (isPortrait) {
      if (state.threePortraitLayout == ThreePanePortraitLayout.equalColumns) {
        // Honour the user's explicit layout choice on every screen size.
        // The previous minimum-column-width fallback silently reverted the
        // selected Columns3 layout on phone-class widths, which read to
        // users as "Columns3 doesn't work at all".
        return _equalRow(context, ref, state, [0, 1, 2]);
      }

      if (state.threePortraitLayout == ThreePanePortraitLayout.equalRows) {
        // Three equal-height panes stacked top-to-bottom in portrait.
        return _equalColumn(context, ref, state, [0, 1, 2]);
      }

      return _portraitDefaultThreePane(context, ref, state);
    }

    if (state.threeLandscapeLayout == ThreePaneLandscapeLayout.equalRows) {
      // Same fix for landscape Rows3: respect the user's explicit choice
      // instead of silently falling back when each row would be < 200 px.
      return _equalColumn(context, ref, state, [0, 1, 2]);
    }

    if (state.threeLandscapeLayout == ThreePaneLandscapeLayout.equalColumns) {
      // Three equal-width panes side-by-side in landscape.
      return _equalRow(context, ref, state, [0, 1, 2]);
    }

    return _landscapeDefaultThreePane(context, ref, state);
  }

  Widget _portraitDefaultThreePane(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
  ) {
    return _SplitContainer(
      axis: Axis.vertical,
      fraction: state.splitV,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(PaneSplit.vertical, f),
      first: _paneAt(context, ref, state, 0),
      second: _SplitContainer(
        axis: Axis.horizontal,
        fraction: state.splitSecondary,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.secondary, f),
        first: _paneAt(context, ref, state, 1),
        second: _paneAt(context, ref, state, 2),
      ),
    );
  }

  Widget _landscapeDefaultThreePane(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
  ) {
    return _SplitContainer(
      axis: Axis.horizontal,
      fraction: state.splitH,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(PaneSplit.horizontal, f),
      first: _paneAt(context, ref, state, 0),
      second: _SplitContainer(
        axis: Axis.vertical,
        fraction: state.splitSecondary,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.secondary, f),
        first: _paneAt(context, ref, state, 1),
        second: _paneAt(context, ref, state, 2),
      ),
    );
  }

  Widget _equalRow(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
    List<int> indices,
  ) {
    final children = <Widget>[];

    for (var i = 0; i < indices.length; i++) {
      if (i > 0) {
        children.add(
          Container(width: _paneGutter, color: Theme.of(context).dividerColor),
        );
      }

      children.add(Expanded(child: _paneAt(context, ref, state, indices[i])));
    }

    return Row(children: children);
  }

  Widget _equalColumn(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
    List<int> indices,
  ) {
    final children = <Widget>[];

    for (var i = 0; i < indices.length; i++) {
      if (i > 0) {
        children.add(
          Container(height: _paneGutter, color: Theme.of(context).dividerColor),
        );
      }

      children.add(Expanded(child: _paneAt(context, ref, state, indices[i])));
    }

    return Column(children: children);
  }

  Widget _fourPaneLayout(BuildContext context, WidgetRef ref, PaneState state) {
    return _SplitContainer(
      axis: Axis.vertical,
      fraction: state.splitV,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(PaneSplit.vertical, f),
      first: _SplitContainer(
        axis: Axis.horizontal,
        fraction: state.splitH,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.horizontal, f),
        first: _paneAt(context, ref, state, 0),
        second: _paneAt(context, ref, state, 1),
      ),
      second: _SplitContainer(
        axis: Axis.horizontal,
        fraction: state.splitSecondary,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.secondary, f),
        first: _paneAt(context, ref, state, 2),
        second: _paneAt(context, ref, state, 3),
      ),
    );
  }

  Widget _paneAt(
    BuildContext context,
    WidgetRef ref,
    PaneState state,
    int index,
  ) {
    final paneId = 'pane-$index';
    final tabId = state.paneTabIds[index];
    final isFocused = state.focusedPaneIndex == index;

    final focusBorderColor = Theme.of(context).colorScheme.primary;
    final overlay = isFocused ? focusedPaneOverlayBuilder?.call(context) : null;

    final paneContent = tabId == null
        ? const ColoredBox(color: Colors.black)
        : ClipRect(
            child: GeckoView(
              key: ValueKey('gecko-$paneId-$tabId'),
              paneId: paneId,
              tabId: tabId,
              focused: isFocused,
            ),
          );

    void requestFocusForPane() {
      final onFocusPane = this.onFocusPane;
      if (onFocusPane != null) {
        onFocusPane(index);
      } else {
        ref.read(paneControllerProvider.notifier).focusPane(index);
      }
    }

    return Semantics(
      label: '${state.mode.semanticLabel}, pane ${index + 1}',
      focused: isFocused,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => requestFocusForPane(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: requestFocusForPane,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              border: Border.all(
                color: isFocused ? focusBorderColor : Colors.transparent,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                paneContent,
                if (overlay != null) Positioned.fill(child: overlay),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitContainer extends StatelessWidget {
  final Axis axis;
  final double fraction;
  final ValueChanged<double> onFractionChanged;
  final Widget first;
  final Widget second;

  const _SplitContainer({
    required this.axis,
    required this.fraction,
    required this.onFractionChanged,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = axis == Axis.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;

        if (extent.isInfinite || extent <= 0) {
          return _flexFallback();
        }

        const totalFlex = 10000;
        final firstFlex = (fraction * totalFlex)
            .clamp(1, totalFlex - 1)
            .toInt();
        final secondFlex = totalFlex - firstFlex;

        final children = <Widget>[
          Expanded(flex: firstFlex, child: first),
          _DraggableDivider(
            axis: axis,
            onDragDelta: (delta) {
              final next =
                  (firstFlex + (delta / extent) * totalFlex) / totalFlex;
              onFractionChanged(next);
            },
          ),
          Expanded(flex: secondFlex, child: second),
        ];

        return axis == Axis.vertical
            ? Column(children: children)
            : Row(children: children);
      },
    );
  }

  Widget _flexFallback() {
    final children = <Widget>[
      Expanded(child: first),
      _DraggableDivider(axis: axis, onDragDelta: (_) {}),
      Expanded(child: second),
    ];

    return axis == Axis.vertical
        ? Column(children: children)
        : Row(children: children);
  }
}

class _DraggableDivider extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDragDelta;

  const _DraggableDivider({required this.axis, required this.onDragDelta});

  @override
  State<_DraggableDivider> createState() => _DraggableDividerState();
}

class _DraggableDividerState extends State<_DraggableDivider> {
  static const double _visualThickness = MultiPaneBrowserView._paneGutter;
  static const double _hitThickness = 3.6;

  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.dividerColor;
    final accent = theme.colorScheme.primary;
    final isVertical = widget.axis == Axis.vertical;

    final cursor = isVertical
        ? SystemMouseCursors.resizeRow
        : SystemMouseCursors.resizeColumn;

    final hitArea = isVertical
        ? const SizedBox(height: _hitThickness)
        : const SizedBox(width: _hitThickness);

    final visualBar = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: isVertical ? double.infinity : _visualThickness,
      height: isVertical ? _visualThickness : double.infinity,
      color: (_dragging || _hovering) ? accent : base,
    );

    return MouseRegion(
      cursor: cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: isVertical
            ? (_) => setState(() => _dragging = true)
            : null,
        onVerticalDragUpdate: isVertical
            ? (d) => widget.onDragDelta(d.delta.dy)
            : null,
        onVerticalDragEnd: isVertical
            ? (_) => setState(() => _dragging = false)
            : null,
        onHorizontalDragStart: isVertical
            ? null
            : (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: isVertical
            ? null
            : (d) => widget.onDragDelta(d.delta.dx),
        onHorizontalDragEnd: isVertical
            ? null
            : (_) => setState(() => _dragging = false),
        child: Stack(
          alignment: Alignment.center,
          children: [hitArea, visualBar],
        ),
      ),
    );
  }
}
