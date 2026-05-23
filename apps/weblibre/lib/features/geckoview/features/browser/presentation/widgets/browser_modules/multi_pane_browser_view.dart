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

class MultiPaneBrowserView extends ConsumerStatefulWidget {
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
  ConsumerState<MultiPaneBrowserView> createState() =>
      _MultiPaneBrowserViewState();
}

class _MultiPaneBrowserViewState extends ConsumerState<MultiPaneBrowserView>
    with TickerProviderStateMixin {
  /// The pane index selected as source for a drag-swap, or null when swap mode
  /// is inactive.
  int? _swapSourceIndex;

  /// Animation controller for the pulsing glow on the swap-source pane.
  late final AnimationController _swapGlowController;
  late final Animation<double> _swapGlowAnim;

  @override
  void initState() {
    super.initState();
    _swapGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _swapGlowAnim = CurvedAnimation(
      parent: _swapGlowController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _swapGlowController.dispose();
    super.dispose();
  }

  void _activateSwapMode(int index) {
    setState(() => _swapSourceIndex = index);
    _swapGlowController.repeat(reverse: true);
  }

  void _cancelSwapMode() {
    setState(() => _swapSourceIndex = null);
    _swapGlowController.stop();
    _swapGlowController.value = 0;
  }

  void _performSwap(int targetIndex) {
    final source = _swapSourceIndex;
    if (source == null || source == targetIndex) {
      _cancelSwapMode();
      return;
    }
    ref.read(paneControllerProvider.notifier).swapPanes(source, targetIndex);
    _cancelSwapMode();
  }

  PaneState get _paneState =>
      widget.paneState ?? ref.watch(paneControllerProvider);

  @override
  Widget build(BuildContext context) {
    final paneState = _paneState;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxHeight >= constraints.maxWidth;
        return _buildLayout(context, paneState, isPortrait, constraints);
      },
    );
  }

  Widget _buildLayout(
    BuildContext context,
    PaneState state,
    bool isPortrait,
    BoxConstraints constraints,
  ) {
    switch (state.mode) {
      case PaneMode.single:
        return _paneAt(context, state, 0);
      case PaneMode.two:
        return _twoPaneLayout(context, state, isPortrait);
      case PaneMode.three:
        return _threePaneLayout(context, state, isPortrait);
      case PaneMode.four:
        return _fourPaneLayout(context, state, constraints);
    }
  }

  Widget _twoPaneLayout(
    BuildContext context,
    PaneState state,
    bool isPortrait,
  ) {
    return _SplitContainer(
      axis: isPortrait ? Axis.vertical : Axis.horizontal,
      fraction: isPortrait ? state.splitV : state.splitH,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(isPortrait ? PaneSplit.vertical : PaneSplit.horizontal, f),
      first: _paneAt(context, state, 0),
      second: _paneAt(context, state, 1),
    );
  }

  Widget _threePaneLayout(
    BuildContext context,
    PaneState state,
    bool isPortrait,
  ) {
    if (isPortrait) {
      if (state.threePortraitLayout == ThreePanePortraitLayout.equalColumns) {
        return _equalRow(context, state, [0, 1, 2]);
      }
      if (state.threePortraitLayout == ThreePanePortraitLayout.equalRows) {
        return _equalColumn(context, state, [0, 1, 2]);
      }
      return _portraitDefaultThreePane(context, state);
    }

    if (state.threeLandscapeLayout == ThreePaneLandscapeLayout.equalRows) {
      return _equalColumn(context, state, [0, 1, 2]);
    }
    if (state.threeLandscapeLayout == ThreePaneLandscapeLayout.equalColumns) {
      return _equalRow(context, state, [0, 1, 2]);
    }
    return _landscapeDefaultThreePane(context, state);
  }

  Widget _portraitDefaultThreePane(BuildContext context, PaneState state) {
    return _SplitContainer(
      axis: Axis.vertical,
      fraction: state.splitV,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(PaneSplit.vertical, f),
      first: _paneAt(context, state, 0),
      second: _SplitContainer(
        axis: Axis.horizontal,
        fraction: state.splitSecondary,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.secondary, f),
        first: _paneAt(context, state, 1),
        second: _paneAt(context, state, 2),
      ),
    );
  }

  Widget _landscapeDefaultThreePane(BuildContext context, PaneState state) {
    return _SplitContainer(
      axis: Axis.horizontal,
      fraction: state.splitH,
      onFractionChanged: (f) => ref
          .read(paneControllerProvider.notifier)
          .setSplit(PaneSplit.horizontal, f),
      first: _paneAt(context, state, 0),
      second: _SplitContainer(
        axis: Axis.vertical,
        fraction: state.splitSecondary,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.secondary, f),
        first: _paneAt(context, state, 1),
        second: _paneAt(context, state, 2),
      ),
    );
  }

  Widget _equalRow(BuildContext context, PaneState state, List<int> indices) {
    final children = <Widget>[];
    for (var i = 0; i < indices.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: MultiPaneBrowserView._paneGutter,
            color: Theme.of(context).dividerColor,
          ),
        );
      }
      children.add(Expanded(child: _paneAt(context, state, indices[i])));
    }
    return Row(children: children);
  }

  Widget _equalColumn(
    BuildContext context,
    PaneState state,
    List<int> indices,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < indices.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            height: MultiPaneBrowserView._paneGutter,
            color: Theme.of(context).dividerColor,
          ),
        );
      }
      children.add(Expanded(child: _paneAt(context, state, indices[i])));
    }
    return Column(children: children);
  }

  Widget _fourPaneLayout(
    BuildContext context,
    PaneState state,
    BoxConstraints constraints,
  ) {
    final grid = _SplitContainer(
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
        first: _paneAt(context, state, 0),
        second: _paneAt(context, state, 1),
      ),
      second: _SplitContainer(
        axis: Axis.horizontal,
        fraction: state.splitSecondary,
        onFractionChanged: (f) => ref
            .read(paneControllerProvider.notifier)
            .setSplit(PaneSplit.secondary, f),
        first: _paneAt(context, state, 2),
        second: _paneAt(context, state, 3),
      ),
    );

    // Overlay a draggable corner handle at the intersection of the H and V
    // splits so the user can resize diagonally in a single gesture.
    if (constraints.maxWidth > 0 && constraints.maxHeight > 0) {
      return Stack(
        children: [
          grid,
          _CornerDragHandle(
            splitH: state.splitH,
            splitV: state.splitV,
            totalWidth: constraints.maxWidth,
            totalHeight: constraints.maxHeight,
            onDrag: (dx, dy) {
              final newH = (state.splitH + dx / constraints.maxWidth).clamp(
                PaneState.minSplit,
                1 - PaneState.minSplit,
              );
              final newV = (state.splitV + dy / constraints.maxHeight).clamp(
                PaneState.minSplit,
                1 - PaneState.minSplit,
              );
              ref
                  .read(paneControllerProvider.notifier)
                  .setSplit(PaneSplit.horizontal, newH);
              ref
                  .read(paneControllerProvider.notifier)
                  .setSplit(PaneSplit.vertical, newV);
            },
          ),
        ],
      );
    }

    return grid;
  }

  Widget _paneAt(BuildContext context, PaneState state, int index) {
    final paneId = 'pane-$index';
    final tabId = state.paneTabIds[index];
    final isFocused = state.focusedPaneIndex == index;
    final swapSource = _swapSourceIndex;
    final isSwapSource = swapSource == index;
    final isSwapMode = swapSource != null;

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

    final focusBorderColor = Theme.of(context).colorScheme.primary;
    final overlay =
        isFocused ? widget.focusedPaneOverlayBuilder?.call(context) : null;

    void requestFocusForPane() {
      final onFocusPane = widget.onFocusPane;
      if (onFocusPane != null) {
        onFocusPane(index);
      } else {
        ref.read(paneControllerProvider.notifier).focusPane(index);
      }
    }

    return Semantics(
      label: '${state.mode.semanticLabel}, pane ${index + 1}',
      focused: isFocused,
      child: _PaneWrapper(
        paneIndex: index,
        isFocused: isFocused,
        isSwapSource: isSwapSource,
        isSwapMode: isSwapMode,
        focusBorderColor: focusBorderColor,
        swapGlowAnim: _swapGlowAnim,
        onFocusRequest: requestFocusForPane,
        onLongPressActivated: _activateSwapMode,
        onSwapRequest: _performSwap,
        onCancelSwap: _cancelSwapMode,
        overlay: overlay,
        child: paneContent,
      ),
    );
  }
}

// ── Pane Wrapper ─────────────────────────────────────────────────────────────

/// Wraps a single pane providing:
///  • Normal focus glow (primary colour, static border).
///  • Long-press hold timer with a fingerprint-style progress ring overlay.
///  • Activated swap-source glow (amber, pulsing – distinguishable from focus).
///  • Drop-target subtle amber border when swap mode is active on another pane.
class _PaneWrapper extends StatefulWidget {
  final int paneIndex;
  final bool isFocused;
  final bool isSwapSource;
  final bool isSwapMode;
  final Color focusBorderColor;
  final Animation<double> swapGlowAnim;
  final VoidCallback onFocusRequest;
  final ValueChanged<int> onLongPressActivated;
  final ValueChanged<int> onSwapRequest;
  final VoidCallback onCancelSwap;
  final Widget? overlay;
  final Widget child;

  const _PaneWrapper({
    required this.paneIndex,
    required this.isFocused,
    required this.isSwapSource,
    required this.isSwapMode,
    required this.focusBorderColor,
    required this.swapGlowAnim,
    required this.onFocusRequest,
    required this.onLongPressActivated,
    required this.onSwapRequest,
    required this.onCancelSwap,
    required this.child,
    this.overlay,
  });

  @override
  State<_PaneWrapper> createState() => _PaneWrapperState();
}

class _PaneWrapperState extends State<_PaneWrapper>
    with SingleTickerProviderStateMixin {
  // Duration a finger must be held before swap mode activates.
  static const _holdDuration = Duration(milliseconds: 650);

  late final AnimationController _holdProgressController;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _holdProgressController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _isHolding) {
          widget.onLongPressActivated(widget.paneIndex);
        }
      });
  }

  @override
  void dispose() {
    _holdProgressController.dispose();
    super.dispose();
  }

  void _startHold() {
    if (widget.isSwapMode) return; // already in swap mode
    setState(() => _isHolding = true);
    _holdProgressController
      ..reset()
      ..forward();
  }

  void _endHold() {
    if (!_isHolding) return;
    setState(() => _isHolding = false);
    if (_holdProgressController.status != AnimationStatus.completed) {
      _holdProgressController.stop();
      _holdProgressController.reset();
    }
  }

  void _handleTap() {
    if (widget.isSwapMode && !widget.isSwapSource) {
      widget.onSwapRequest(widget.paneIndex);
    } else if (widget.isSwapSource) {
      widget.onCancelSwap();
    } else {
      widget.onFocusRequest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swapColor = theme.colorScheme.tertiary.withValues(alpha: 0.9);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        widget.onFocusRequest();
        _startHold();
      },
      onPointerUp: (_) => _endHold(),
      onPointerCancel: (_) => _endHold(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation:
              widget.isSwapSource ? widget.swapGlowAnim : _holdProgressController,
          builder: (context, child) {
            // ── Border color and width ────────────────────────────────────
            Color borderColor;
            double borderWidth;

            if (widget.isSwapSource) {
              // Pulsing amber glow on the selected source pane.
              final pulse = widget.swapGlowAnim.value;
              borderWidth = 2.5 + pulse * 2.0;
              borderColor = swapColor.withValues(alpha: 0.6 + pulse * 0.4);
            } else if (widget.isSwapMode) {
              // Subtle amber outline on potential drop targets.
              borderWidth = 1.0;
              borderColor = swapColor.withValues(alpha: 0.35);
            } else if (widget.isFocused) {
              // Standard focus glow (primary colour, static).
              borderWidth = 1.0;
              borderColor = widget.focusBorderColor;
            } else {
              borderWidth = 0;
              borderColor = Colors.transparent;
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                border: Border.all(
                  color: borderColor,
                  width: borderWidth,
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (widget.overlay != null)
                Positioned.fill(child: widget.overlay!),
              // ── Hold-progress ring overlay ───────────────────────────
              if (_isHolding)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _holdProgressController,
                      builder: (context, _) {
                        return _HoldProgressOverlay(
                          progress: _holdProgressController.value,
                          color: swapColor,
                        );
                      },
                    ),
                  ),
                ),
              // ── Swap-mode source indicator ───────────────────────────
              if (widget.isSwapSource)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: widget.swapGlowAnim,
                      builder: (context, _) {
                        return Opacity(
                          opacity: 0.6 + widget.swapGlowAnim.value * 0.4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: swapColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Tap another pane to swap',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a semi-transparent radial progress ring centred on the pane, giving
/// the user visual feedback that a long-press swap is about to activate —
/// similar to a fingerprint unlock timer.
class _HoldProgressOverlay extends StatelessWidget {
  final double progress;
  final Color color;

  const _HoldProgressOverlay({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // Background circle
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
              ),
            ),
            // Circular progress
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 3.5,
              color: color,
              backgroundColor: color.withValues(alpha: 0.25),
            ),
            // Centre icon
            Icon(Icons.swap_horiz_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Corner Diagonal Drag Handle ───────────────────────────────────────────────

/// A small draggable diamond/circle handle placed at the intersection of the
/// primary H and V splits in the 4-pane layout.  Dragging it diagonally
/// updates both splits simultaneously.
class _CornerDragHandle extends StatefulWidget {
  final double splitH;
  final double splitV;
  final double totalWidth;
  final double totalHeight;
  final void Function(double dx, double dy) onDrag;

  const _CornerDragHandle({
    required this.splitH,
    required this.splitV,
    required this.totalWidth,
    required this.totalHeight,
    required this.onDrag,
  });

  @override
  State<_CornerDragHandle> createState() => _CornerDragHandleState();
}

class _CornerDragHandleState extends State<_CornerDragHandle>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  bool _dragging = false;
  late final AnimationController _idleAnim;

  @override
  void initState() {
    super.initState();
    _idleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idleAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    // Pixel position of the intersection
    final cx = widget.splitH * widget.totalWidth;
    final cy = widget.splitV * widget.totalHeight;

    const handleRadius = 14.0;
    const hitRadius = 22.0;

    return Positioned(
      left: cx - hitRadius,
      top: cy - hitRadius,
      width: hitRadius * 2,
      height: hitRadius * 2,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() => _dragging = true),
          onPanUpdate: (d) =>
              widget.onDrag(d.delta.dx, d.delta.dy),
          onPanEnd: (_) => setState(() => _dragging = false),
          child: AnimatedBuilder(
            animation: _idleAnim,
            builder: (context, _) {
              final glowAlpha = _dragging || _hovering
                  ? 0.85
                  : 0.40 + _idleAnim.value * 0.30;

              return Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width:
                      (_dragging || _hovering) ? handleRadius * 2 : handleRadius * 1.5,
                  height:
                      (_dragging || _hovering) ? handleRadius * 2 : handleRadius * 1.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: glowAlpha),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: glowAlpha * 0.6),
                        blurRadius:
                            (_dragging || _hovering) ? 14 : 6 + _idleAnim.value * 6,
                        spreadRadius: (_dragging || _hovering) ? 3 : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.open_with_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Split Container ───────────────────────────────────────────────────────────

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
        final firstFlex = (fraction * totalFlex).clamp(1, totalFlex - 1).toInt();
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

// ── Draggable Divider ─────────────────────────────────────────────────────────

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