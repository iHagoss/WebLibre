/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

import eu.weblibre.flutter_mozilla_components.api.GeckoBrowserApiImpl

/**
 * Thin native adapter that ties together the existing Android Components
 * `BrowserStore` (the real runtime source of truth for sessions / tabs)
 * and the native pane-fragment attachment logic implemented in
 * [GeckoBrowserApiImpl] for the WebLibre multi-pane feature.
 *
 * This object intentionally does NOT:
 *
 * - own or persist its own tab list — the Dart-side `TabRepository`
 *   remains responsible for persisted tab/container metadata,
 * - construct another tab database — Android Components' `BrowserStore`
 *   in [Components.core] continues to hold the live `TabSessionState`
 *   list and is the only runtime session source of truth,
 * - construct another `GeckoRuntime` — [EngineProvider] still owns the
 *   single shared runtime instance used by every pane.
 *
 * Its sole purpose is to expose a small, stable surface that
 * [GeckoBrowserApiImpl] (and tests) can call to query known tab ids and
 * to attach a tab to a pane container, so that future pane-related
 * features have a single place to plug into without poking at internal
 * Android Components state directly.
 */
object BrowserSessionManager {

    /**
     * Optional hook used by [GeckoBrowserApiImpl] to delegate the actual
     * fragment attachment. It is set at plugin attach time and lets us
     * keep all FragmentManager / Activity access in one place while still
     * letting tests stub the manager out.
     */
    @Volatile
    private var paneAttacher: ((Long, String, String, Boolean) -> Boolean)? = null

    private val components
        get() = GlobalComponents.components

    /**
     * Returns the ids of every tab currently known to Android Components'
     * `BrowserStore`. Order matches `state.tabs`, so callers that need a
     * stable ordering for pane seeding can rely on it.
     *
     * Returns an empty list if components are not initialized yet.
     */
    fun getKnownTabIds(): List<String> {
        return components?.core?.store?.state?.tabs?.map { it.id } ?: emptyList()
    }

    /**
     * Returns the currently selected tab id from `BrowserStore`, or `null`
     * if no tab is selected (or components are not initialized).
     */
    fun getSelectedTabId(): String? {
        return components?.core?.store?.state?.selectedTabId
    }

    /**
     * Returns `true` if [tabId] exists in `BrowserStore`. Useful for guard
     * clauses before calling [attachTabToPane].
     */
    fun hasTab(tabId: String): Boolean {
        val tabs = components?.core?.store?.state?.tabs ?: return false
        return tabs.any { it.id == tabId }
    }

    /**
     * Register the attachment implementation. Called by
     * [GeckoBrowserApiImpl] during plugin attach so this manager can
     * delegate the real FragmentManager work without depending on the
     * implementation class directly.
     */
    fun setPaneAttacher(attacher: (Long, String, String, Boolean) -> Boolean) {
        paneAttacher = attacher
    }

    /**
     * Clear the attachment implementation, e.g. during plugin detach.
     */
    fun clearPaneAttacher() {
        paneAttacher = null
    }

    /**
     * Attach an existing tab (already present in `BrowserStore`) to the
     * native pane container identified by [platformViewId] / [paneId].
     *
     * This returns `false` when:
     *
     * - components are not initialized,
     * - the tab is not known to `BrowserStore`,
     * - no native pane attacher has been registered yet,
     * - the FragmentManager / container view is not ready (the attacher
     *   itself returns `false` in this case).
     *
     * In all of those cases Dart-side retry logic should call again on a
     * later frame.
     */
    fun attachTabToPane(
        platformViewId: Long,
        paneId: String,
        tabId: String,
        focused: Boolean,
    ): Boolean {
        if (!hasTab(tabId)) {
            return false
        }
        val attacher = paneAttacher ?: return false
        return attacher(platformViewId, paneId, tabId, focused)
    }
}
