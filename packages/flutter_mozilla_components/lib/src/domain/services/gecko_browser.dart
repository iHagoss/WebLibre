/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter_mozilla_components/src/pigeons/gecko.g.dart';

final _apiInstance = GeckoBrowserApi();

class GeckoBrowserService {
  final GeckoBrowserApi _api;

  GeckoBrowserService({GeckoBrowserApi? api}) : _api = api ?? _apiInstance;

  Future<String> getGeckoVersion() {
    return _api.getGeckoVersion();
  }

  Future<void> initialize(
    String profileFolder,
    LogLevel logLevel,
    ContentBlocking contentBlocking,
    AddonCollection? addonCollection,
    String? fxaServerOverride,
    String? syncTokenServerOverride, [
    GeckoEngineSettings? startupSettings,
    String? startupUBlockFilterListsPref,
    bool clearStartupUBlockFilterListsPref = false,
  ]) {
    return _api.initialize(
      profileFolder,
      logLevel,
      contentBlocking,
      addonCollection,
      fxaServerOverride,
      syncTokenServerOverride,
      startupSettings,
      startupUBlockFilterListsPref,
      clearStartupUBlockFilterListsPref,
    );
  }

  Future<bool> showNativeFragment() {
    return _api.showNativeFragment();
  }

  /// Pane-aware variant of [showNativeFragment] used by split-pane layouts.
  ///
  /// Does not create a GeckoRuntime; it only attaches the existing tab
  /// session identified by [tabId] to the native container backing
  /// [platformViewId] for the logical pane [paneId]. When [focused] is true
  /// the pane becomes the focused pane for global toolbar/keyboard state.
  Future<bool> showNativeFragmentForPane({
    required int platformViewId,
    required String paneId,
    required String tabId,
    required bool focused,
  }) {
    return _api.showNativeFragmentForPane(
      platformViewId,
      paneId,
      tabId,
      focused,
    );
  }

  Future<void> onTrimMemory(int level) {
    return _api.onTrimMemory(level);
  }

  Future<void> openInCustomTab({
    required Uri url,
    required bool private,
    String? contextId,
  }) {
    return _api.openInCustomTab(
      url: url.toString(),
      private: private,
      contextId: contextId,
    );
  }

  Future<bool> isDefaultBrowser() {
    return _api.isDefaultBrowser();
  }

  Future<void> requestDefaultBrowser() {
    return _api.requestDefaultBrowser();
  }

  Future<bool> pickUnifiedPushDistributor() {
    return _api.pickUnifiedPushDistributor();
  }

  Future<void> shutdown() {
    return _api.shutdown();
  }
}
