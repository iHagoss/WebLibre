/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.app.Activity
import android.view.ViewGroup
import android.widget.FrameLayout
import eu.weblibre.flutter_mozilla_components.ext.EventSequence
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoStateEvents
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for the native FrameLayout container that hosts a [BrowserFragment]
 * (one per Flutter `GeckoView` widget).
 *
 * Multi-pane support:
 *
 * - Each created platform view now receives a freshly generated Android
 *   view id via [View.generateViewId], so that multiple panes can coexist
 *   without clashing on the legacy fixed `0xBEEF` id.
 * - The fixed [containerId] passed in by the host plugin is still used as
 *   a fallback for the very first / legacy single-pane platform view
 *   (i.e. when no creation params with a `paneId` are present). This
 *   preserves existing single-pane startup so [BrowserScreen] keeps
 *   working before the Dart-side `paneControllerProvider` lands.
 * - The mapping `platformViewId -> generatedContainerId` is recorded in
 *   [MultiPaneRegistry] so that
 *   [api.GeckoBrowserApiImpl.showNativeFragmentForPane] can find the right
 *   native container when Dart asks for a pane.
 *
 * `paneId` and `tabId` are read from `creationParams` when present and
 * forwarded to [MultiPaneRegistry] / preserved for later attach calls. The
 * factory does not create [GeckoSession]s or fragments itself; that work
 * still happens via `BrowserFragment.create(sessionId = ...)` from
 * `GeckoBrowserApiImpl`.
 */
class GeckoViewFactory(
    private val activityProvider: () -> Activity?,
    private val containerId: Int,
    private val flutterEvents: GeckoStateEvents
    ) : PlatformViewFactory(
    StandardMessageCodec.INSTANCE) {

    companion object {
        /**
         * Notified when a pane's native container receives an ACTION_DOWN
         * touch event. The Dart side wires this up to focus the matching
         * pane so the user's tap on a pane actually makes it the active
         * pane (otherwise the Flutter `GestureDetector` wrapping the
         * platform view never sees the tap because the platform view
         * absorbs all touch events).
         *
         * The listener is set from `GeckoBrowserApiImpl.attachBinding`
         * once the binary messenger is available.
         */
        @Volatile
        var paneTouchListener: ((paneId: String) -> Unit)? = null
    }

    @Suppress("UNCHECKED_CAST")
    override fun create(context: Context?, id: Int, args: Any?): PlatformView {
        val activity = activityProvider()
            ?: throw IllegalStateException("No activity available when creating GeckoView platform view")

        // Creation params are optional. They are sent from the pane-aware
        // `GeckoView(paneId: ..., tabId: ...)` widget. If they're missing we
        // fall back to legacy single-pane behavior.
        val paramsMap = args as? Map<String, Any?>
        val paneId = paramsMap?.get("paneId") as? String
        val tabId = paramsMap?.get("tabId") as? String
        val isPaneAware = paneId != null

        // For pane-aware views always allocate a unique Android view id so
        // four containers can coexist. The legacy single-pane container
        // keeps using `containerId` for backward compatibility.
        val resolvedContainerId = if (isPaneAware) View.generateViewId() else containerId

        MultiPaneRegistry.registerPlatformView(id, resolvedContainerId)
        if (paneId != null && tabId != null) {
            MultiPaneRegistry.bindPane(paneId, tabId)
        }

        return NativeFragmentView(
            activity = activity,
            containerId = resolvedContainerId,
            platformViewId = id,
            paneId = paneId,
            flutterEvents = flutterEvents,
        )
    }
}

private class NativeFragmentView(
    activity: Activity?,
    containerId: Int,
    private val platformViewId: Int,
    private val paneId: String?,
    private val flutterEvents: GeckoStateEvents
) : PlatformView {
    private val components by lazy {
        requireNotNull(GlobalComponents.components) { "Components not initialized" }
    }

    private val container: View

    init {
        val vParams: ViewGroup.LayoutParams =
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
            )

        // Ensure activity is not null before creating the container
        if (activity == null) {
            throw IllegalStateException("Activity cannot be null when creating NativeFragmentView")
        }

        // Use a touch-intercepting FrameLayout so we can detect ACTION_DOWN
        // on this pane and forward focus to the Dart side. Flutter platform
        // views absorb all touch events before any wrapping Flutter
        // GestureDetector can react, so a Dart-only solution cannot detect
        // taps on the pane. Intercepting in dispatchTouchEvent runs BEFORE
        // the child fragment view handles the gesture and does NOT consume
        // the event (super.dispatchTouchEvent is still called), so web
        // content scrolling/tapping continues to work normally.
        container = PaneTouchInterceptingFrameLayout(activity, paneId).apply {
            layoutParams = vParams
            id = containerId
        }
    }

    override fun onFlutterViewAttached(flutterView: View) {
        super.onFlutterViewAttached(flutterView)

        components.engineReportedInitialized = false
        flutterEvents.onViewReadyStateChange(EventSequence.next(), true) { _ -> }
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        // Disposing a pane only detaches the visual container; tabs/sessions
        // are owned by BrowserStore and must not be closed here.
        MultiPaneRegistry.unregisterPlatformView(platformViewId)
    }
}

/**
 * FrameLayout that notifies [GeckoViewFactory.paneTouchListener] on every
 * ACTION_DOWN it sees. The touch event is then passed to the parent
 * implementation unchanged so the GeckoView/BrowserFragment beneath this
 * container still receives the gesture (so scrolling, link taps, form
 * input etc. keep working).
 */
private class PaneTouchInterceptingFrameLayout(
    context: Context,
    private val paneId: String?,
) : FrameLayout(context) {
    override fun dispatchTouchEvent(ev: MotionEvent?): Boolean {
        if (ev != null && ev.actionMasked == MotionEvent.ACTION_DOWN) {
            val pid = paneId
            if (pid != null) {
                // Best-effort: never let a listener exception break touch
                // dispatch for the underlying web content.
                try {
                    GeckoViewFactory.paneTouchListener?.invoke(pid)
                } catch (_: Throwable) {
                    // Swallowed intentionally — focus is a UX nicety; if it
                    // fails we must still pass the touch down to the engine.
                }
            }
        }
        return super.dispatchTouchEvent(ev)
    }
}
