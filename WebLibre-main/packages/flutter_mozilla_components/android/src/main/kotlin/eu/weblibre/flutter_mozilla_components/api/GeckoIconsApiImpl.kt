/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components.api

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import eu.weblibre.flutter_mozilla_components.GlobalComponents
import eu.weblibre.flutter_mozilla_components.ext.toWebPBytes
import eu.weblibre.flutter_mozilla_components.pigeons.*
import kotlinx.coroutines.*
import mozilla.components.browser.icons.BrowserIcons
import mozilla.components.browser.icons.Icon
import mozilla.components.concept.engine.manifest.Size as HtmlSize
import mozilla.components.feature.addons.logger

private typealias MozillaIconRequest = mozilla.components.browser.icons.IconRequest
private typealias MozillaIconSize = mozilla.components.browser.icons.IconRequest.Size
private typealias MozillaIconResource = mozilla.components.browser.icons.IconRequest.Resource
private typealias MozillaIconResourceType = mozilla.components.browser.icons.IconRequest.Resource.Type

/**
 * Implementation of GeckoIconsApi that handles icon loading and processing
 */
class GeckoIconsApiImpl : GeckoIconsApi {
    companion object {
        private const val TAG = "GeckoIconsApi"
        private val coroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    }

    private val components by lazy {
        requireNotNull(GlobalComponents.components) { "Components not initialized" }
    }

    override fun loadIcon(request: IconRequest, callback: (Result<IconResult>) -> Unit) {
        coroutineScope.launch {
            try {
                val mozillaRequest = request.toMozillaIconRequest()
                logger.debug("$TAG: Loading icon for URL: ${request.url}")

                val result = loadIconAsync(mozillaRequest)
                withContext(Dispatchers.Main) {
                    callback(Result.success(result))
                }
            } catch (e: Exception) {
                logger.error("$TAG: Failed to load icon", e)
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    private suspend fun loadIconAsync(request: MozillaIconRequest): IconResult {
        return try {
            val result = components.core.icons.loadIcon(request).await()
            val imageBytes = result.bitmap.toWebPBytes()
            IconResult(
                image = imageBytes,
                maskable = result.maskable,
                color = result.color?.toLong(),
                source = result.source.toApiSource()
            )
        } catch (e: RuntimeException) {
            if (e is CancellationException) throw e

            if (e is IllegalArgumentException || e.isSvgIconDecoderCrash()) {
                logger.warn(
                    "$TAG: Falling back to generated globe icon for ${request.url}; " +
                        "SVG favicon decoder rejected the resource: ${e.message}"
                )
                fallbackGlobeIconResult()
            } else {
                logger.error("$TAG: Error in loadIconAsync", e)
                throw e
            }
        } catch (e: Exception) {
            logger.error("$TAG: Error in loadIconAsync", e)
            throw e
        }
    }

    private fun Throwable.isSvgIconDecoderCrash(): Boolean {
        return stackTrace.any { frame ->
            frame.className.contains("SvgIconDecoder") ||
                frame.className.contains("BrowserIcons")
        }
    }

    private fun fallbackGlobeIconResult(): IconResult {
        val size = 64
        val center = size / 2f
        val radius = 23f
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(96, 112, 128)
            style = Paint.Style.STROKE
            strokeWidth = 3.5f
        }

        canvas.drawCircle(center, center, radius, paint)
        canvas.drawLine(center - radius, center, center + radius, center, paint)
        canvas.drawOval(RectF(center - 9f, center - radius, center + 9f, center + radius), paint)
        canvas.drawArc(
            RectF(center - radius, center - 14f, center + radius, center + 14f),
            0f,
            360f,
            false,
            paint
        )

        return IconResult(
            image = bitmap.toWebPBytes(),
            maskable = false,
            color = Color.rgb(96, 112, 128).toLong(),
            source = IconSource.GENERATOR
        )
    }

    private fun IconRequest.toMozillaIconRequest(): MozillaIconRequest {
        return MozillaIconRequest(
            url = url,
            size = size.toMozillaSize(),
            color = color?.toInt(),
            waitOnNetworkLoad = waitOnNetworkLoad,
            isPrivate = isPrivate,
            resources = resources.filterNotNull().map { it.toMozillaResource() }
        )
    }

    private fun IconSize.toMozillaSize(): MozillaIconSize = when (this) {
        IconSize.DEFAULT_SIZE -> MozillaIconSize.DEFAULT
        IconSize.LAUNCHER -> MozillaIconSize.LAUNCHER
        IconSize.LAUNCHER_ADAPTIVE -> MozillaIconSize.LAUNCHER_ADAPTIVE
    }

    private fun Resource.toMozillaResource(): MozillaIconResource {
        return MozillaIconResource(
            url = url,
            mimeType = mimeType,
            maskable = maskable,
            type = type.toMozillaType(),
            sizes = sizes.filterNotNull().map {
                HtmlSize(it.height.toInt(), it.width.toInt())
            }
        )
    }

    private fun IconType.toMozillaType(): MozillaIconResourceType = when (this) {
        IconType.FAVICON -> MozillaIconResourceType.FAVICON
        IconType.APPLE_TOUCH_ICON -> MozillaIconResourceType.APPLE_TOUCH_ICON
        IconType.FLUID_ICON -> MozillaIconResourceType.FLUID_ICON
        IconType.IMAGE_SRC -> MozillaIconResourceType.IMAGE_SRC
        IconType.OPEN_GRAPH -> MozillaIconResourceType.OPENGRAPH
        IconType.TWITTER -> MozillaIconResourceType.TWITTER
        IconType.MICROSOFT_TILE -> MozillaIconResourceType.MICROSOFT_TILE
        IconType.TIPPY_TOP -> MozillaIconResourceType.TIPPY_TOP
        IconType.MANIFEST_ICON -> MozillaIconResourceType.MANIFEST_ICON
    }

    private fun Icon.Source.toApiSource(): IconSource = when (this) {
        Icon.Source.GENERATOR -> IconSource.GENERATOR
        Icon.Source.DOWNLOAD -> IconSource.DOWNLOAD
        Icon.Source.INLINE -> IconSource.INLINE
        Icon.Source.MEMORY -> IconSource.MEMORY
        Icon.Source.DISK -> IconSource.DISK
    }
}
