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

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mozilla_components/flutter_mozilla_components.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:weblibre/core/logger.dart';
import 'package:weblibre/features/geckoview/domain/entities/tab_container_selection.dart';
import 'package:weblibre/features/geckoview/domain/providers/tab_list.dart';
import 'package:weblibre/features/geckoview/domain/providers/tab_state.dart';
import 'package:weblibre/features/geckoview/domain/repositories/tab.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_layout.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_mode.dart';
import 'package:weblibre/features/geckoview/features/browser/domain/entities/pane_state.dart';
import 'package:weblibre/features/geckoview/features/tabs/data/entities/tab_mode.dart';
import 'package:weblibre/features/user/data/providers.dart';

part 'pane_controller.g.dart';

enum PaneSplit { horizontal, vertical, secondary }

const List<String> _seedPaneUrls = [
  'https://example.com',
  'https://mozilla.org',
  'https://developer.android.com',
  'https://wikipedia.org',
];

@Riverpod(keepAlive: true)
class PaneController extends _$PaneController {
  bool _seeded = false;
  bool _seedingInProgress = false;
  bool _restoredPanePreferences = false;

  static const _paneSettingsPartitionKey = 'paneController';
  static const _threePortraitLayoutSettingKey = 'threePanePortraitLayout';

  static const _paneFocusChannel = MethodChannel(
    'eu.weblibre.flutter_mozilla_components/pane_focus',
  );

  @override
  PaneState build() {
    _paneFocusChannel.setMethodCallHandler(_onPaneFocusMethodCall);
    ref.onDispose(() {
      _paneFocusChannel.setMethodCallHandler(null);
    });

    unawaited(_restorePersistedPanePreferences());

    return PaneState.initial();
  }

  Future<void> _restorePersistedPanePreferences() async {
    if (_restoredPanePreferences) return;
    _restoredPanePreferences = true;

    try {
      final db = ref.read(userDatabaseProvider);
      final value = await db.settingDao.getSettingValue(
        _threePortraitLayoutSettingKey,
      );
      final storedLayoutName = value?.readAs(
        DriftSqlType.string,
        db.typeMapping,
      );
      final storedLayout = _parseThreePortraitLayout(storedLayoutName);

      if (storedLayout != null) {
        state = state.copyWith(threePortraitLayout: storedLayout);
      }
    } catch (error, stackTrace) {
      logger.w(
        'Failed to restore pane layout preferences',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  ThreePanePortraitLayout? _parseThreePortraitLayout(String? value) {
    if (value == null) return null;

    for (final layout in ThreePanePortraitLayout.values) {
      if (layout.name == value) return layout;
    }

    return null;
  }

  Future<void> _persistThreePortraitLayout(
    ThreePanePortraitLayout layout,
  ) async {
    try {
      await ref
          .read(userDatabaseProvider)
          .settingDao
          .updateSetting(
            _threePortraitLayoutSettingKey,
            _paneSettingsPartitionKey,
            layout.name,
          );
    } catch (error, stackTrace) {
      logger.w(
        'Failed to persist 3-pane portrait layout preference',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<dynamic> _onPaneFocusMethodCall(MethodCall call) async {
    if (call.method != 'onPaneTouched') return null;
    final paneId = call.arguments;
    if (paneId is! String) return null;

    final dash = paneId.lastIndexOf('-');
    if (dash < 0) return null;

    final index = int.tryParse(paneId.substring(dash + 1));
    if (index == null) return null;

    focusPane(index);
    return null;
  }

  void setMode(PaneMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  void focusPane(int index) {
    if (index < 0 || index >= state.visiblePaneCount) return;
    if (state.focusedPaneIndex == index) return;

    state = state.copyWith(focusedPaneIndex: index);

    final tabId = state.paneTabIds[index];
    if (tabId != null) {
      unawaitedSelectTab(tabId);
    }
  }

  void assignTabToPane(
    int index,
    String tabId, {
    bool disposePreviousOnSwap = false,
  }) {
    if (index < 0 || index >= PaneState.paneSlotCount) return;
    if (state.paneTabIds[index] == tabId) return;

    final previousTabId = state.paneTabIds[index];
    state = state.withTabAt(index, tabId);

    if (!disposePreviousOnSwap || previousTabId == null) return;

    final previousTabState = ref.read(tabStatesProvider)[previousTabId];
    final previousContextId =
        previousTabState?.isolationContextId ?? previousTabState?.contextId;
    if (previousContextId == null) return;

    unawaited(
      ref
          .read(tabRepositoryProvider.notifier)
          .cleanupIsolationContextIfEmpty(previousContextId)
          .catchError((Object error, StackTrace stackTrace) {
            logger.e(
              'Failed to cleanup isolation context $previousContextId after '
              'pane swap',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  void setSplit(PaneSplit split, double fraction) {
    switch (split) {
      case PaneSplit.horizontal:
        if (state.splitH == fraction) return;
        state = state.copyWith(splitH: fraction);
      case PaneSplit.vertical:
        if (state.splitV == fraction) return;
        state = state.copyWith(splitV: fraction);
      case PaneSplit.secondary:
        if (state.splitSecondary == fraction) return;
        state = state.copyWith(splitSecondary: fraction);
    }
  }

  void setThreePortraitLayout(ThreePanePortraitLayout layout) {
    if (state.threePortraitLayout == layout) return;

    state = state.copyWith(threePortraitLayout: layout);
    unawaited(_persistThreePortraitLayout(layout));
  }

  void setThreeLandscapeLayout(ThreePaneLandscapeLayout layout) {
    if (state.threeLandscapeLayout == layout) return;
    state = state.copyWith(threeLandscapeLayout: layout);
  }

  Future<void> ensureStartupPanesSeeded() async {
    if (_seeded || _seedingInProgress) return;
    _seedingInProgress = true;

    try {
      ref.read(tabListProvider);
      await GeckoTabService().syncEvents(onTabListChange: true);

      final existingTabIds = ref.read(tabListProvider).value;
      final paneTabIds = List<String?>.from(state.paneTabIds);

      final reusable = existingTabIds.take(PaneState.paneSlotCount).toList();
      for (var i = 0; i < reusable.length; i++) {
        paneTabIds[i] = reusable[i];
      }

      for (var i = 0; i < PaneState.paneSlotCount; i++) {
        if (paneTabIds[i] != null) continue;

        final url = i < _seedPaneUrls.length ? _seedPaneUrls[i] : null;
        if (url == null) continue;

        try {
          final newTabId = await ref
              .read(tabRepositoryProvider.notifier)
              .addTab(
                tabMode: TabMode.newIsolated(),
                url: Uri.parse(url),
                selectTab: i == 0 && existingTabIds.isEmpty,
                containerSelection: const TabContainerSelection.unassigned(),
              );
          paneTabIds[i] = newTabId;
        } catch (error, stackTrace) {
          logger.e(
            'Failed to seed pane tab $i ($url)',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      state = state.copyWith(paneTabIds: paneTabIds, focusedPaneIndex: 0);
      _seeded = true;
    } finally {
      _seedingInProgress = false;
    }
  }

  void unawaitedSelectTab(String tabId) {
    unawaited(
      ref.read(tabRepositoryProvider.notifier).selectTab(tabId).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        logger.e(
          'Failed to select focused pane tab $tabId',
          error: error,
          stackTrace: stackTrace,
        );
        return false;
      }),
    );
  }
}
