/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

/**
 * Tracks native platform-view containers and pane-to-tab bindings for the
 * WebLibre multi-pane GeckoView feature.
 *
 * This registry intentionally holds **attachment state only**. It does NOT:
 *
 * - own or create [GeckoSession]s,
 * - own or create a [GeckoRuntime] (that remains the single instance
 *   provided by [EngineProvider]),
 * - duplicate the tab list (Android Components' `BrowserStore` remains the
 *   real session source of truth, and the Dart-side `TabRepository` remains
 *   responsible for persisted tab/container metadata).
 *
 * The registry maps:
 *
 * - Flutter platform-view id → native [android.widget.FrameLayout] container
 *   view id, so that [api.GeckoBrowserApiImpl.showNativeFragmentForPane]
 *   can locate the correct native container when Dart asks for a pane.
 * - Pane id (e.g. `pane-0`) → tab id, so that focus / re-attach decisions
 *   can be made without re-querying the Dart side every frame.
 *
 * It also tracks which pane id is currently focused. The focused pane drives
 * global toolbar, keyboard and back-button behavior, even though all panes
 * share one [BrowserStore].
 *
 * All mutating operations are synchronized on the registry instance to make
 * it safe to call from any UI/main-thread callbacks dispatched by Flutter
 * platform-view lifecycle events. Cleanup should be performed by callers
 * during platform-view dispose, see [unregisterPlatformView].
 */
object MultiPaneRegistry {

    /** Mapping from Flutter platform-view id to native container view id. */
    private val platformViewContainers: MutableMap<Int, Int> = mutableMapOf()

    /** Mapping from stable Dart pane id to current tab id attached to that pane. */
    private val paneTabBindings: MutableMap<String, String> = mutableMapOf()

    /** The pane id that is currently focused, or `null` if no pane is focused yet. */
    private var focusedPaneId: String? = null

    /**
     * Register a Flutter platform-view id with the native container view id
     * it was created for.
     *
     * Called from `GeckoViewFactory.create` after `View.generateViewId()`
     * picks a unique id for the new native [android.widget.FrameLayout].
     */
    @Synchronized
    fun registerPlatformView(platformViewId: Int, containerViewId: Int) {
        platformViewContainers[platformViewId] = containerViewId
    }

    /**
     * Unregister a Flutter platform-view id when the platform view is disposed.
     *
     * Note: disposing a pane only detaches the visual fragment from the
     * native container; the tab / [GeckoSession] continues to live in
     * `BrowserStore` and can be re-attached to another pane later.
     */
    @Synchronized
    fun unregisterPlatformView(platformViewId: Int) {
        platformViewContainers.remove(platformViewId)
    }

    /** Returns the native container view id for [platformViewId], or `null` if not registered. */
    @Synchronized
    fun getContainerViewId(platformViewId: Int): Int? {
        return platformViewContainers[platformViewId]
    }

    /**
     * Bind a stable Dart pane id to a tab id.
     *
     * This is attachment metadata only; the underlying [GeckoSession] is
     * still owned by Android Components and must already exist in
     * `BrowserStore` before being attached.
     */
    @Synchronized
    fun bindPane(paneId: String, tabId: String) {
        paneTabBindings[paneId] = tabId
    }

    /** Returns the tab id currently bound to [paneId], or `null` if unbound. */
    @Synchronized
    fun getTabIdForPane(paneId: String): String? {
        return paneTabBindings[paneId]
    }

    /**
     * Update which pane id is currently focused.
     *
     * The focused pane drives global toolbar / keyboard / back-button
     * behavior across the four GeckoView fragments.
     */
    @Synchronized
    fun setFocusedPane(paneId: String) {
        focusedPaneId = paneId
    }

    /** Returns `true` if [paneId] is the currently focused pane. */
    @Synchronized
    fun isFocusedPane(paneId: String): Boolean {
        return focusedPaneId == paneId
    }

    /** Returns the currently focused pane id, or `null` if none is focused. */
    @Synchronized
    fun getFocusedPaneId(): String? {
        return focusedPaneId
    }

    /**
     * Test-only / debug helper that drops every entry in the registry.
     *
     * Production code should rely on platform-view dispose callbacks to
     * call [unregisterPlatformView] for each pane instead of clearing
     * everything wholesale.
     */
    @Synchronized
    fun clearForTesting() {
        platformViewContainers.clear()
        paneTabBindings.clear()
        focusedPaneId = null
    }
}
