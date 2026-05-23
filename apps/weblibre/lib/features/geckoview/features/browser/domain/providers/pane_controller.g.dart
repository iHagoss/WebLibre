// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pane_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PaneController)
final paneControllerProvider = PaneControllerProvider._();

final class PaneControllerProvider
    extends $NotifierProvider<PaneController, PaneState> {
  PaneControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'paneControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$paneControllerHash();

  @$internal
  @override
  PaneController create() => PaneController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PaneState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PaneState>(value),
    );
  }
}

String _$paneControllerHash() => r'10f635052ff77dcd9eb7182deb16648e48b54487';

abstract class _$PaneController extends $Notifier<PaneState> {
  PaneState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PaneState, PaneState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PaneState, PaneState>,
              PaneState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
