/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.annotation.CallSuper
import mozilla.components.concept.engine.EngineView
import mozilla.components.support.base.feature.UserInteractionHandler

/**
 * Fragment used for browsing the web within the main app.
 *
 * Pane-aware behavior:
 * - When a [PANE_ID_KEY] argument is supplied, the created [EngineView] is registered as a
 *   pane engine view via [Components.registerPaneEngineView]. This allows multiple
 *   [BrowserFragment] instances to coexist (one per visible pane) while keeping the legacy
 *   single-pane behavior available for callers that omit the pane id.
 * - Destroying a pane fragment unregisters only that pane's engine view and never closes the
 *   underlying tab/session, because Android Components keeps the [mozilla.components.concept.engine.EngineSession]
 *   in [Components.core.store] independently of the fragment lifecycle.
 */
class BrowserFragment() : BaseBrowserFragment(), UserInteractionHandler {

    // Local reference to the EngineView created for this fragment so we can cleanly
    // unregister it from the pane registry in onDestroyView without depending on
    // the (private) tracking in BaseBrowserFragment.
    private var paneEngineView: EngineView? = null

    override fun createEngine(components: Components): EngineView {
        //We cannot introduce here our wrapped context since a activity type is required to make features work correctly like context menu
        return components.core.engine.createView(requireContext()).apply {
           selectionActionDelegate = components.selectionAction
        }.also { engineView ->
            val currentPaneId = paneId
            if (currentPaneId != null) {
                // Pane-aware: register with the multi-pane registry. We do not touch
                // mainBrowserEngineView so other panes are not disturbed.
                paneEngineView = engineView
                components.registerPaneEngineView(currentPaneId, engineView)
            } else {
                // Legacy single-pane: keep existing behavior so non-pane callers still work.
                components.mainBrowserEngineView = engineView
            }
        }
    }

    @Deprecated("Deprecated in Java")
    @CallSuper
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super<BaseBrowserFragment>.onActivityResult(requestCode, data, resultCode)
    }

    @Suppress("LongMethod")
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
    }

    override fun onEngineSetupComplete() {
        GlobalComponents.viewportApi?.applyPendingToolbarHeight()
    }

    override fun onBackPressed(): Boolean =
        super.readerViewFeature.onBackPressed() || super.onBackPressed()

    override fun onDestroyView() {
        val currentPaneId = paneId
        val engineView = paneEngineView
        super.onDestroyView()
        if (currentPaneId != null) {
            // Only unregister this pane's engine view. Do not close the tab/session;
            // Android Components keeps the EngineSession in BrowserStore independently
            // of fragment lifecycle.
            if (engineView != null) {
                components.unregisterPaneEngineView(currentPaneId, engineView)
            }
            paneEngineView = null
        } else {
            // Legacy single-pane cleanup.
            components.mainBrowserEngineView = null
        }
    }

    companion object {
        /**
         * Create a [BrowserFragment].
         *
         * @param sessionId the tab/session id to attach. May be null for legacy callers.
         * @param paneId optional pane identifier (e.g. "pane-0"). When provided the fragment
         *               behaves as one tile in a multi-pane layout and registers itself in
         *               [Components.paneEngineViews] instead of [Components.mainBrowserEngineView].
         */
        fun create(sessionId: String? = null, paneId: String? = null) = BrowserFragment().apply {
            arguments = Bundle().apply {
                putSessionId(sessionId)
                putPaneId(paneId)
            }
        }
    }
}
