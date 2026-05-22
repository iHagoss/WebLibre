/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

package eu.weblibre.flutter_mozilla_components

import android.content.Context
import eu.weblibre.flutter_mozilla_components.feature.ContainerProxyFeature
import eu.weblibre.flutter_mozilla_components.feature.CookieManagerFeature
import eu.weblibre.flutter_mozilla_components.feature.BrowserExtensionFeature
import eu.weblibre.flutter_mozilla_components.feature.MLEngineFeature
import eu.weblibre.flutter_mozilla_components.pigeons.BounceTrackingProtectionMode
import eu.weblibre.flutter_mozilla_components.pigeons.BrowserExtensionEvents
import eu.weblibre.flutter_mozilla_components.pigeons.GeckoStateEvents
import eu.weblibre.flutter_mozilla_components.pigeons.QueryParameterStripping
import mozilla.components.browser.engine.gecko.GeckoEngine
import mozilla.components.browser.engine.gecko.fetch.GeckoViewFetchClient
import mozilla.components.concept.engine.DefaultSettings
import mozilla.components.concept.engine.Engine
import mozilla.components.concept.engine.EngineSession
import mozilla.components.concept.fetch.Client
import mozilla.components.feature.webcompat.WebCompatFeature
import mozilla.components.support.base.log.Log
import mozilla.components.support.base.log.logger.Logger
import mozilla.components.support.webextensions.BuiltInWebExtensionController
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings

object EngineProvider {
    private var runtime: GeckoRuntime? = null

    private val components: Components
        get() = requireNotNull(GlobalComponents.components) { "Components not initialized" }

    @Synchronized
    fun getOrCreateRuntime(context: Context): GeckoRuntime {
        if (runtime == null) {
            Logger.debug("Creating Runtime")
            val builder = GeckoRuntimeSettings.Builder()
            val contentBlocking = ContentBlocking.Settings.Builder();

            contentBlocking.bounceTrackingProtectionMode(
                when (components.contentBlocking.bounceTrackingProtectionMode) {
                    BounceTrackingProtectionMode.ENABLED -> EngineSession.BounceTrackingProtectionMode.ENABLED.mode
                    BounceTrackingProtectionMode.DISABLED -> EngineSession.BounceTrackingProtectionMode.DISABLED.mode
                    BounceTrackingProtectionMode.ENABLED_STANDBY -> EngineSession.BounceTrackingProtectionMode.ENABLED_STANDBY.mode
                    BounceTrackingProtectionMode.ENABLED_DRY_RUN -> EngineSession.BounceTrackingProtectionMode.ENABLED_DRY_RUN.mode
                }
            )

            contentBlocking.queryParameterStrippingEnabled(
                when (components.contentBlocking.queryParameterStripping) {
                    QueryParameterStripping.ENABLED -> true
                    QueryParameterStripping.DISABLED -> false
                    QueryParameterStripping.PRIVATE_ONLY -> false
                }
            )

            contentBlocking.queryParameterStrippingPrivateBrowsingEnabled(
                when (components.contentBlocking.queryParameterStripping) {
                    QueryParameterStripping.ENABLED -> true
                    QueryParameterStripping.DISABLED -> false
                    QueryParameterStripping.PRIVATE_ONLY -> true
                }
            )

            if (components.contentBlocking.queryParameterStrippingAllowList.isNotEmpty()) {
                contentBlocking.queryParameterStrippingAllowList(
                    components.contentBlocking.queryParameterStrippingAllowList,
                )
            }
            if (components.contentBlocking.queryParameterStrippingStripList.isNotEmpty()) {
                contentBlocking.queryParameterStrippingStripList(
                    components.contentBlocking.queryParameterStrippingStripList,
                )
            }

//            if (isCrashReportActive) {
//                builder.crashHandler(CrashHandlerService::class.java)
//            }

            // About config it's no longer enabled by default
            builder.aboutConfigEnabled(true)
            builder.extensionsProcessEnabled(true)
            builder.extensionsWebAPIEnabled(true)
            //builder.debugLogging(components.logLevel == Log.Priority.DEBUG)
            builder.consoleOutput(components.logLevel == Log.Priority.DEBUG)
            builder.contentBlocking(contentBlocking.build())
            builder.locales(arrayOf("en-US", "en")) // Will be overridden later

            // Apply builder-only settings from startup config
            GlobalComponents.startupSettings?.let { settings ->
                settings.fissionEnabled?.let { builder.fissionEnabled(it) }
                settings.isolatedProcessEnabled?.let { builder.isolatedProcessEnabled(it) }
                settings.appZygoteProcessEnabled?.let { builder.appZygoteProcessEnabled(it) }
                settings.extensionsWebAPIEnabled?.let { builder.extensionsWebAPIEnabled(it) }
                settings.displayDensityOverride?.let { builder.displayDensityOverride(it.toFloat()) }
                val screenWidth = settings.screenWidthOverride
                val screenHeight = settings.screenHeightOverride
                if (screenWidth != null && screenHeight != null && screenWidth > 0 && screenHeight > 0) {
                    builder.screenSizeOverride(screenWidth.toInt(), screenHeight.toInt())
                }
            }

            runtime = GeckoRuntime.create(context, builder.build())
        }

        return runtime!!
    }

    fun createEngine(
        context: Context,
        defaultSettings: DefaultSettings,
        extensionEvents: BrowserExtensionEvents,
        stateEvents: GeckoStateEvents
    ): Engine {
        Logger.debug("Creating Engine")
        val runtime = getOrCreateRuntime(context)

        return GeckoEngine(context, defaultSettings, runtime).also {
            WebCompatFeature.install(it)
            //CookieManagerFeature.install(it)
            ContainerProxyFeature.install(it, stateEvents)
            BrowserExtensionFeature.install(it, extensionEvents)
            MLEngineFeature.install(it)

            // Task 40 — startup warning
            // "addons.xpi WARN Force scan SCOPE_APPLICATION (app-builtin-addons
            //  location missing from XPIStates)" is logged by Gecko's internal
            // XPIProvider during GeckoRuntime.create(), BEFORE the
            // BuiltInWebExtensionController.install(...) calls below run.
            // Mozilla Android Components / GeckoView do not expose a public
            // Java/Kotlin API to register the `app-builtin-addons` XPI location
            // ahead of that first scan, so the warning cannot be suppressed
            // from here without either (a) shipping a Gecko prefs file via
            // GeckoRuntimeSettings.Builder.configFilePath() that sets
            // extensions.startupScanScopes=0, or (b) a future GeckoView API.
            // The warning is cosmetic and does not affect built-in extension
            // installation below — they install correctly on the same engine.

            //Install extensions early
            BuiltInWebExtensionController(
                "readability-extract@weblibre.eu",
                "resource://android/assets/extensions/readability_extract/",
                "mozacReaderExtract",
            ).install(it)

            BuiltInWebExtensionController(
                "readerview@mozac.org",
                "resource://android/assets/extensions/readerview/",
                "mozacReaderview",
            ).install(it)

            // Cross-pane coordinator: one global background script + content
            // script in every pane/tab. Installed on the same shared engine
            // used by all panes — no extra runtime or engine is created.
            try {
                BuiltInWebExtensionController(
                    "cross-pane-coordinator@weblibre.eu",
                    "resource://android/assets/extensions/cross_pane_coordinator/",
                    "crossPaneCoordinator",
                ).install(it)
                Logger.debug("Installed cross-pane-coordinator extension")
            } catch (e: Throwable) {
                Logger.error("Failed to install cross-pane-coordinator extension", e)
            }
        }
    }

    fun createClient(context: Context): Client {
        Logger.debug("Fetching Client")
        val runtime = getOrCreateRuntime(context)
        return GeckoViewFetchClient(context, runtime)
    }

    @Synchronized
    fun shutdown() {
        runtime?.let {
            Logger.debug("Shutting down GeckoRuntime")
            it.shutdown()
            runtime = null
        }
    }
}
