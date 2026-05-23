/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import eu.weblibre.flutter_mozilla_components.components.Core
import eu.weblibre.flutter_mozilla_components.components.BackgroundServices
import eu.weblibre.flutter_mozilla_components.components.Events
import eu.weblibre.flutter_mozilla_components.components.Features
import eu.weblibre.flutter_mozilla_components.components.Push
import eu.weblibre.flutter_mozilla_components.components.Search
import eu.weblibre.flutter_mozilla_components.components.Services
import eu.weblibre.flutter_mozilla_components.components.UseCases
import eu.weblibre.flutter_mozilla_components.pigeons.AddonCollection
import eu.weblibre.flutter_mozilla_components.pigeons.BrowserExtensionEvents
import eu.weblibre.flutter_mozilla_components.pigeons.ContentBlocking
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoAddonEvents
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoStateEvents
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoSyncStateEvents
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoTabContentEvents
import eu.weblibre.flutter_mozilla_components.pigeons.ReaderViewController
import mozilla.components.concept.engine.EngineView
import mozilla.components.concept.engine.selection.SelectionActionDelegate
import mozilla.components.feature.downloads.DefaultFileSizeFormatter
import mozilla.components.feature.downloads.DownloadEstimator
import mozilla.components.feature.downloads.FileSizeFormatter
import mozilla.components.support.base.android.NotificationsDelegate
import mozilla.components.support.base.log.Log
import mozilla.components.support.utils.DateTimeProvider
import mozilla.components.support.utils.DefaultDateTimeProvider

class Components(val profileApplicationContext: ProfileContext,
                 val flutterEvents: GeckoStateEvents,
                 val readerViewController: ReaderViewController,
                 val selectionAction: SelectionActionDelegate,
                 val logLevel: Log.Priority,
                 val contentBlocking: ContentBlocking,
                 val addonCollection: AddonCollection?,
                 val fxaServerOverride: String?,
                 val syncTokenServerOverride: String?,
                 val addonEvents: GeckoAddonEvents,
                 private val tabContentEvents: GeckoTabContentEvents,
                 private val extensionEvents: BrowserExtensionEvents,
                 private val syncStateEvents: GeckoSyncStateEvents?,
) {
    val core by lazy { Core(profileApplicationContext, this, flutterEvents, extensionEvents) }
    val backgroundServices by lazy {
        BackgroundServices(
            context = profileApplicationContext,
            browserStore = lazy { core.store },
            historyStorage = core.lazyHistoryStorage,
            bookmarkStorage = core.lazyBookmarksStorage,
            remoteTabsStorage = core.lazyRemoteTabsStorage,
            fxaServerOverride = fxaServerOverride,
            syncTokenServerOverride = syncTokenServerOverride,
            syncStateEvents = syncStateEvents,
        )
    }
    val events by lazy { Events(flutterEvents) }
    val useCases by lazy { UseCases(profileApplicationContext, core.engine, core.store, core.webAppShortcutManager) }
    val services by lazy {
        Services(
            profileApplicationContext,
            core.store,
            useCases.tabsUseCases,
            backgroundServices.accountManager,
            core.engine,
            backgroundServices.serverConfig,
        )
    }
    val features by lazy { Features(core.engine, core.store, addonEvents, tabContentEvents) }
    val search by lazy { Search(profileApplicationContext, core, useCases) }
    val push by lazy { Push(this) }

    var mainBrowserEngineView: EngineView? = null
    var externalAppEngineView: EngineView? = null

    var activeEngineView: EngineView? = null

    /**
     * Multi-pane support: per-pane [EngineView]s registered by each
     * [BrowserFragment] when it carries a `paneId` argument.
     *
     * The key is the stable Dart pane id (e.g. `pane-0`). A pane's
     * fragment registers itself in `createEngine` and unregisters in
     * `onDestroyView` so destroying or remounting one pane does not
     * affect other panes' engine views.
     *
     * The single-pane code path (no `paneId` argument) keeps assigning
     * [mainBrowserEngineView] as before for backward compatibility.
     */
    val paneEngineViews: MutableMap<String, EngineView> = mutableMapOf()

    /** Pane id whose [EngineView] currently drives global UI behaviour. */
    var focusedPaneId: String? = null

    /**
     * Listeners notified after [focusPaneEngineView] updates [focusedPaneId]
     * and [activeEngineView]. Receives the newly focused pane id.
     *
     * Used by [BaseBrowserFragment] to start/stop per-pane global features
     * (keyboard visibility, scroll-handling toolbar driver) when focus moves
     * between panes — Task 43 — so the auto-hide toolbar behaviour follows
     * whichever pane the user just tapped.
     */
    private val paneFocusListeners: MutableList<(String) -> Unit> = mutableListOf()

    /** Register a [listener] to be notified on focus changes. Idempotent. */
    fun addPaneFocusListener(listener: (String) -> Unit) {
        if (!paneFocusListeners.contains(listener)) {
            paneFocusListeners.add(listener)
        }
    }

    /** Unregister a previously-added focus [listener]. */
    fun removePaneFocusListener(listener: (String) -> Unit) {
        paneFocusListeners.remove(listener)
    }

    /**
     * Register an [EngineView] for the given pane. Called by
     * [BrowserFragment.createEngine] when the fragment was created with a
     * pane id. Idempotent for the same `(paneId, engineView)` pair.
     *
     * Task 47 — After mutating the per-pane registry the pane viewport
     * policy is re-applied for every currently-registered pane so the
     * new pane count is reflected in each pane's compositor scale.
     */
    fun registerPaneEngineView(paneId: String, engineView: EngineView) {
        paneEngineViews[paneId] = engineView
        if (focusedPaneId == paneId) {
            activeEngineView = engineView
        }
        PaneViewportPolicy.refresh(this)
    }

    /**
     * Unregister an [EngineView] for the given pane.
     *
     * Only clears [activeEngineView] when the unregistered view was the
     * currently active one, so destroying an unfocused pane never wipes
     * the focused pane's active view.
     *
     * Task 47 — After mutating the per-pane registry the pane viewport
     * policy is re-applied for every remaining pane so the reduced
     * pane count is reflected in their compositor scale.
     */
    fun unregisterPaneEngineView(paneId: String, engineView: EngineView) {
        val current = paneEngineViews[paneId]
        if (current === engineView) {
            paneEngineViews.remove(paneId)
        }
        if (activeEngineView === engineView) {
            activeEngineView = null
        }
        PaneViewportPolicy.refresh(this)
    }

    /**
     * Mark [paneId] as focused and, if it has a registered engine view,
     * promote it to [activeEngineView] so global features (toolbar,
     * keyboard, viewport) target the right pane.
     *
     * Notifies registered [paneFocusListeners] after state is updated so
     * pane fragments can re-wire their dynamic-toolbar/scroll listeners
     * (Task 43).
     */
    fun focusPaneEngineView(paneId: String) {
        focusedPaneId = paneId
        paneEngineViews[paneId]?.let { activeEngineView = it }
        // Snapshot so a listener that removes itself does not mutate the
        // list during iteration.
        paneFocusListeners.toList().forEach { it.invoke(paneId) }
    }
    
    var engineReportedInitialized = false

    private val notificationManagerCompat = NotificationManagerCompat.from(profileApplicationContext)
    val notificationsDelegate: NotificationsDelegate by lazy {
        NotificationsDelegate(
            notificationManagerCompat,
        )
    }

    val fileSizeFormatter: FileSizeFormatter by lazy { DefaultFileSizeFormatter(profileApplicationContext) }

    val dateTimeProvider: DateTimeProvider by lazy { DefaultDateTimeProvider() }

    val downloadEstimator: DownloadEstimator by lazy { DownloadEstimator(dateTimeProvider = dateTimeProvider) }
}
