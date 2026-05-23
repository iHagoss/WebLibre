/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components.api

import eu.weblibre.flutter_mozilla_components.GlobalComponents
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoViewportApi

/**
 * Implementation of GeckoViewportApi that controls GeckoView's viewport behavior
 * for dynamic toolbar and keyboard handling.
 *
 * Toolbar height and vertical clipping target the main browser's EngineView specifically,
 * not the active/foreground EngineView. This prevents toolbar settings from leaking
 * to PWA/Custom Tab EngineViews.
 *
 * If the main browser EngineView is not yet available when setDynamicToolbarMaxHeight
 * is called, the value is stored and applied when the EngineView becomes available.
 */
class GeckoViewportApiImpl : GeckoViewportApi {
    private val components by lazy {
        requireNotNull(GlobalComponents.components) { "Components not initialized" }
    }

    private var pendingToolbarHeight: Int? = null

    /**
     * Sets the maximum height that dynamic toolbars (top + bottom) can occupy.
     *
     * In single-pane mode this targets the main browser EngineView. In
     * multi-pane mode (Task 43) it targets the focused pane's EngineView
     * via [Components.activeEngineView] so the auto-hide toolbar follows
     * the pane the user is interacting with. If neither is available yet,
     * the height is stored and applied later via [applyPendingToolbarHeight].
     */
    override fun setDynamicToolbarMaxHeight(heightPx: Long) {
        val height = heightPx.toInt()

        val engineView = components.activeEngineView ?: components.mainBrowserEngineView
        if (engineView == null) {
            pendingToolbarHeight = height
            return
        }

        pendingToolbarHeight = null
        engineView.setDynamicToolbarMaxHeight(height)
    }

    /**
     * Applies any pending toolbar height to the focused/main browser EngineView.
     * Called when an EngineView becomes available.
     */
    fun applyPendingToolbarHeight() {
        val pending = pendingToolbarHeight ?: return
        val engineView = components.activeEngineView ?: components.mainBrowserEngineView ?: return
        pendingToolbarHeight = null
        engineView.setDynamicToolbarMaxHeight(pending)
    }

    /**
     * Sets the vertical clipping offset for the GeckoView content.
     *
     * In multi-pane mode (Task 43) this targets the focused pane's
     * EngineView; in single-pane it targets the main browser EngineView.
     */
    override fun setVerticalClipping(clippingPx: Long) {
        val clipping = clippingPx.toInt()

        val engineView = components.activeEngineView ?: components.mainBrowserEngineView
        if (engineView == null) {
            return
        }

        engineView.setVerticalClipping(clipping)
    }
}
