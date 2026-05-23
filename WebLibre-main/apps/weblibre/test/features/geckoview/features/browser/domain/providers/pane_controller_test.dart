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

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_mode.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_state.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/providers/pane_controller.dart';

// Unit tests for `PaneController` and the multi-pane state model behind it.
//
// These tests directly cover controller mutations that only touch in-memory
// state. The controller's startup seeding path calls into `tabRepositoryProvider`,
// which transitively requires Android plugin channels and a database — neither
// of which are appropriate for a pure `flutter test` run.
//
// All `PaneController` mutations are thin wrappers around the operations
// validated here (`copyWith(mode: ...)`, `withTabAt(...)`, the focus-clamp
// invariant in `PaneState`'s constructor, etc.), so this covers the
// behavioral contract requested in TASK.md Task 34.
void main() {
  group('PaneMode', () {
    test('paneCount matches enum value', () {
      expect(PaneMode.single.paneCount, 1);
      expect(PaneMode.two.paneCount, 2);
      expect(PaneMode.three.paneCount, 3);
      expect(PaneMode.four.paneCount, 4);
    });

    test('display labels are short for phone toolbars', () {
      for (final mode in PaneMode.values) {
        expect(mode.displayLabel.length, lessThanOrEqualTo(2));
      }
    });

    test('next/previous wrap around', () {
      expect(PaneMode.single.next, PaneMode.two);
      expect(PaneMode.four.next, PaneMode.single);
      expect(PaneMode.single.previous, PaneMode.four);
      expect(PaneMode.two.previous, PaneMode.single);
    });

    test('fromPaneCount maps known values and falls back to single', () {
      expect(PaneMode.fromPaneCount(1), PaneMode.single);
      expect(PaneMode.fromPaneCount(2), PaneMode.two);
      expect(PaneMode.fromPaneCount(3), PaneMode.three);
      expect(PaneMode.fromPaneCount(4), PaneMode.four);
      expect(PaneMode.fromPaneCount(0), PaneMode.single);
      expect(PaneMode.fromPaneCount(99), PaneMode.single);
    });
  });

  group('PaneState defaults', () {
    test('initial state is single-pane with no assignments', () {
      final state = PaneState.initial();
      expect(state.mode, PaneMode.single);
      expect(state.visiblePaneCount, 1);
      expect(state.focusedPaneIndex, 0);
      expect(state.paneTabIds.length, PaneState.paneSlotCount);
      for (final id in state.paneTabIds) {
        expect(id, isNull);
      }
      expect(state.focusedTabId, isNull);
    });
  });

  group('PaneController direct state mutations', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('default mode is single pane', () {
      final state = container.read(paneControllerProvider);

      expect(state.mode, PaneMode.single);
      expect(state.visiblePaneCount, 1);
      expect(state.focusedPaneIndex, 0);
    });

    test('setMode changes visible pane count without closing assignments', () {
      final controller = container.read(paneControllerProvider.notifier);

      controller.assignTabToPane(0, 'tab-a');
      controller.assignTabToPane(1, 'tab-b');
      controller.assignTabToPane(2, 'tab-c');
      controller.assignTabToPane(3, 'tab-d');

      controller.setMode(PaneMode.two);
      expect(container.read(paneControllerProvider).visiblePaneCount, 2);
      expect(container.read(paneControllerProvider).visibleTabIds, [
        'tab-a',
        'tab-b',
      ]);

      controller.setMode(PaneMode.three);
      expect(container.read(paneControllerProvider).visiblePaneCount, 3);
      expect(container.read(paneControllerProvider).visibleTabIds, [
        'tab-a',
        'tab-b',
        'tab-c',
      ]);

      controller.setMode(PaneMode.four);
      expect(container.read(paneControllerProvider).visiblePaneCount, 4);
      expect(container.read(paneControllerProvider).paneTabIds, [
        'tab-a',
        'tab-b',
        'tab-c',
        'tab-d',
      ]);
    });

    test('focus index remains valid when reducing pane count', () {
      final controller = container.read(paneControllerProvider.notifier);

      controller.setMode(PaneMode.four);
      controller.focusPane(3);
      expect(container.read(paneControllerProvider).focusedPaneIndex, 3);

      controller.setMode(PaneMode.two);
      expect(container.read(paneControllerProvider).focusedPaneIndex, 1);

      controller.setMode(PaneMode.single);
      expect(container.read(paneControllerProvider).focusedPaneIndex, 0);
    });
  });

  group('PaneState mode switching (simulates PaneController.setMode)', () {
    test('switching mode preserves pane tab id assignments', () {
      var state = PaneState.initial()
          .withTabAt(0, 'tab-a')
          .withTabAt(1, 'tab-b')
          .withTabAt(2, 'tab-c')
          .withTabAt(3, 'tab-d');

      state = state.copyWith(mode: PaneMode.four);
      expect(state.visibleTabIds, ['tab-a', 'tab-b', 'tab-c', 'tab-d']);

      state = state.copyWith(mode: PaneMode.single);
      expect(state.visiblePaneCount, 1);
      // Hidden slots are preserved even when only one pane is visible.
      expect(state.paneTabIds, ['tab-a', 'tab-b', 'tab-c', 'tab-d']);

      state = state.copyWith(mode: PaneMode.four);
      expect(state.visibleTabIds, ['tab-a', 'tab-b', 'tab-c', 'tab-d']);
    });

    test('reducing pane count clamps focus into valid range', () {
      var state = PaneState.initial().copyWith(
        mode: PaneMode.four,
        focusedPaneIndex: 3,
      );
      expect(state.focusedPaneIndex, 3);

      state = state.copyWith(mode: PaneMode.two);
      expect(state.visiblePaneCount, 2);
      expect(state.focusedPaneIndex, 1);

      state = state.copyWith(mode: PaneMode.single);
      expect(state.visiblePaneCount, 1);
      expect(state.focusedPaneIndex, 0);
    });

    test('expanding pane count keeps existing focus', () {
      var state = PaneState.initial().copyWith(
        mode: PaneMode.two,
        focusedPaneIndex: 1,
      );
      state = state.copyWith(mode: PaneMode.four);
      expect(state.focusedPaneIndex, 1);
    });
  });

  group('PaneState.withTabAt (simulates PaneController.assignTabToPane)', () {
    test('assigns tab to slot and ignores out-of-range index', () {
      var state = PaneState.initial();
      state = state.withTabAt(2, 'tab-x');
      expect(state.paneTabIds[2], 'tab-x');

      final unchanged = state.withTabAt(-1, 'oops');
      expect(unchanged, equals(state));

      final stillUnchanged = state.withTabAt(99, 'oops');
      expect(stillUnchanged, equals(state));
    });

    test('focusedTabId tracks the focused slot', () {
      final state = PaneState.initial()
          .copyWith(mode: PaneMode.two, focusedPaneIndex: 1)
          .withTabAt(0, 'left')
          .withTabAt(1, 'right');
      expect(state.focusedTabId, 'right');
    });
  });

  group('PaneState equality', () {
    test('two states with same data compare equal', () {
      final a = PaneState.initial()
          .copyWith(mode: PaneMode.three)
          .withTabAt(0, 'tab-1')
          .withTabAt(1, 'tab-2');
      final b = PaneState.initial()
          .copyWith(mode: PaneMode.three)
          .withTabAt(0, 'tab-1')
          .withTabAt(1, 'tab-2');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
