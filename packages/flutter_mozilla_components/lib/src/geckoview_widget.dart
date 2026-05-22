/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mozilla_components/src/domain/services/gecko_browser.dart';

class GeckoView extends StatefulWidget {
  final Future<void> Function()? preInitializationStep;
  final Future<void> Function()? postInitializationStep;

  /// Optional logical pane identifier (e.g. `pane-0` .. `pane-3`).
  ///
  /// When [paneId] and [tabId] are both provided the widget uses the
  /// pane-aware native attachment path so multiple `GeckoView`s can coexist,
  /// each showing a distinct tab session. When either is null the legacy
  /// single-pane attachment is used to preserve existing behavior.
  final String? paneId;

  /// Optional tab id this pane should display. Must be a tab id known to
  /// Android Components' BrowserStore. The pane will attach to that tab's
  /// existing EngineSession without recreating it.
  final String? tabId;

  /// Whether this pane is the focused pane. Used by the native side to
  /// route global toolbar/keyboard/viewport behavior to a single pane.
  final bool focused;

  const GeckoView({
    super.key,
    this.preInitializationStep,
    this.postInitializationStep,
    this.paneId,
    this.tabId,
    this.focused = true,
  });

  @override
  State<GeckoView> createState() => _GeckoViewState();
}

class _GeckoViewState extends State<GeckoView> {
  static const platform = MethodChannel(
    'eu.weblibre.flutter_mozilla_components/trim_memory',
  );

  final browserService = GeckoBrowserService();
  late final AppLifecycleListener _listener;

  /// Platform-view id assigned by the framework once the native view is
  /// created. Needed to re-attach the pane on widget updates and on resume.
  int? _platformViewId;

  bool get _isPaneAware => widget.paneId != null && widget.tabId != null;

  @override
  void initState() {
    super.initState();
    _setupMethodCallHandler();
    _listener = AppLifecycleListener(
      onResume: () async {
        // Make sure fragment becomes visible again after resume in case native
        // resources have been disposed.
        await _reattach();
      },
    );
  }

  void _setupMethodCallHandler() {
    platform.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onTrimMemory') {
        await browserService.onTrimMemory(call.arguments as int);
      }
    });
  }

  Future<bool> _reattach() async {
    if (_isPaneAware && _platformViewId != null) {
      return _showNativeFragmentForPane();
    }
    return _showNativeFragment();
  }

  Future<bool> _showNativeFragment({
    int maxRetries = 100,

    /// Default is about one frame.
    Duration retryDelay = const Duration(milliseconds: 1000 ~/ 60),
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      final result = await browserService.showNativeFragment();

      if (result) {
        developer.log(
          'Fragment ATTACHED after $attempt tries',
          name: 'GeckoView',
        );
        return true;
      }

      if (attempt < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }

    developer.log(
      'Fragment FAILED after $maxRetries tries',
      name: 'GeckoView',
      level: 900,
    );
    return false;
  }

  Future<bool> _showNativeFragmentForPane({
    int maxRetries = 100,
    Duration retryDelay = const Duration(milliseconds: 1000 ~/ 60),
  }) async {
    final platformViewId = _platformViewId;
    final paneId = widget.paneId;
    final tabId = widget.tabId;
    if (platformViewId == null || paneId == null || tabId == null) {
      return false;
    }

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      final result = await browserService.showNativeFragmentForPane(
        platformViewId: platformViewId,
        paneId: paneId,
        tabId: tabId,
        focused: widget.focused,
      );

      if (result) {
        developer.log(
          'Pane fragment ATTACHED ($paneId -> $tabId) after $attempt tries',
          name: 'GeckoView',
        );
        return true;
      }

      if (attempt < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }

    developer.log(
      'Pane fragment FAILED ($paneId -> $tabId) after $maxRetries tries',
      name: 'GeckoView',
      level: 900,
    );
    return false;
  }

  @override
  void didUpdateWidget(covariant GeckoView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_isPaneAware) return;
    if (_platformViewId == null) return;

    final changedTab = oldWidget.tabId != widget.tabId;
    final changedPane = oldWidget.paneId != widget.paneId;
    final changedFocus = oldWidget.focused != widget.focused;

    if (!changedTab && !changedPane && !changedFocus) return;

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await _showNativeFragmentForPane();
    });
  }

  @override
  void dispose() {
    platform.setMethodCallHandler(null);
    _listener.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: 'eu.weblibre/gecko',
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        final creationParams = <String, Object?>{};
        if (widget.paneId != null) {
          creationParams['paneId'] = widget.paneId;
        }
        if (widget.tabId != null) {
          creationParams['tabId'] = widget.tabId;
        }
        creationParams['focused'] = widget.focused;

        return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'eu.weblibre/gecko',
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          )
          ..addOnPlatformViewCreatedListener((value) {
            _platformViewId = value;
            params.onPlatformViewCreated(value);

            SchedulerBinding.instance.addPostFrameCallback((_) async {
              await widget.preInitializationStep?.call();

              if (_isPaneAware) {
                await _showNativeFragmentForPane();
              } else {
                await _showNativeFragment();
              }
              await widget.postInitializationStep?.call();
            });
          })
          // ignore: discarded_futures that hos it is done in docs
          ..create();
      },
    );
  }
}
