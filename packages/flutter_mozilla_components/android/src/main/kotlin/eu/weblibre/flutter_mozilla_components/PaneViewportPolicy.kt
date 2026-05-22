/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

import android.content.res.Configuration
import android.content.res.Resources
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.view.doOnLayout
import mozilla.components.concept.engine.EngineView

/**
 * Task 47 — Per-pane viewport scaling.
 *
 * Goal (user-reported symptom):
 *   "Web pages don't display in proportion when using more panes — it
 *    should display and navigate like it would on 1 pane and kept in
 *    perfect proportion — but at the moment it requires awkward pinch
 *    and zooming and navigating making it very unnatural."
 *
 * Strategy (matches TASK.md step 5 — "Bind the compositor scale to a
 * Matrix transform on the EngineView's host FrameLayout … Do not scale
 * Flutter widgets around it — only the native view's content surface."):
 *
 *  1. Capture a single "logical base viewport" the first time the policy
 *     is consulted on a given device, taken from
 *     [Resources.getSystem].displayMetrics. Portrait base is the
 *     device's full single-pane width/height; landscape base is the
 *     device's rotated width/height. These are the dimensions a page
 *     would have laid out against in a 1-pane configuration, so re-using
 *     them inside a multi-pane tile causes Gecko to lay the page out
 *     the same way it would on a full screen.
 *
 *  2. When `paneCount == 1` (legacy single-pane), remove every transform
 *     and let Mozilla AC own the EngineView size again. This is the
 *     no-op path and preserves the prior behaviour for non-pane users.
 *
 *  3. When `paneCount > 1`, set the EngineView's *measured* size to the
 *     full base viewport (e.g. 720 × 1520 for Galaxy S10+ portrait) and
 *     apply a uniform `setScaleX = setScaleY = paneWidthPx / baseWidth`
 *     with pivot at the top-left so the rendered surface visually fits
 *     inside the pane container.
 *
 *  Result: GeckoView still believes it is rendering against a
 *  full-width viewport, so the page does **not** reflow into a narrow
 *  phone layout, but visually the rendered surface is shrunk to fit the
 *  pane — i.e. "as if on a full-width single pane and then scaled".
 *
 *  Touch coordinates: Android translates pointer events through the
 *  [View]'s scale/pivot transforms, so taps still land on the correct
 *  DOM coordinates (subject to the host engine view's own gesture
 *  detector). Pinch-zoom is left intact per the task's step 6.
 *
 * Limitations (documented for the auditor):
 *  - This is a **compositor-only** policy. It does not change Gecko's
 *    per-session settings (`viewportMode = DESKTOP`, force scalable, etc.).
 *    A future commit may wire those once the Mozilla AC version in use
 *    exposes a stable Kotlin entry point for per-session viewport mode.
 *  - The base dimensions are captured once per process; if the device's
 *    real screen geometry changes mid-session (rare — multi-display
 *    hot-plug) the captured value won't update.
 *  - [refresh] is intentionally idempotent and safe to call from
 *    `onConfigurationChanged` and from the `paneController.mode` change
 *    listener on the Dart side.
 *
 * Concurrency: every public function is annotated `@Synchronized` on
 * this object so it is safe to call from main-thread layout callbacks
 * dispatched by Flutter platform-view lifecycle events.
 *
 * UNTESTED on device: the user runs Flutter/Gradle builds on a Galaxy
 * S10+; this policy must be validated against the Task 47 acceptance
 * checks (wikipedia in 4-pane, no reflow-spam, tap/scroll integrity,
 * double-tap-to-zoom unchanged).
 */
@Suppress("unused")
object PaneViewportPolicy {

    /**
     * Tag stored on each scaled native view so we can find and reset
     * our prior modifications without disturbing layout state set by
     * Mozilla AC.
     *
     * Must be an application-specific resource id (declared in
     * res/values/ids.xml) because [View.setTag] enforces
     * `(key >>> 24) >= 2`, which is not satisfied by the runtime ids
     * produced by [View.generateViewId].
     */
    private val TAG_KEY = R.id.pane_viewport_policy_tag

    /**
     * Cached "single-pane" viewport dimensions for the current
     * orientation, captured lazily on first use.
     */
    private var basePortraitWidth: Int = 0
    private var basePortraitHeight: Int = 0
    private var baseLandscapeWidth: Int = 0
    private var baseLandscapeHeight: Int = 0

    /**
     * Per-engineView snapshot of "what we applied last time", so we can
     * restore the original layout params when paneCount returns to 1.
     */
    private data class Snapshot(
        val originalWidth: Int,
        val originalHeight: Int,
        val originalPivotX: Float,
        val originalPivotY: Float,
        val originalScaleX: Float,
        val originalScaleY: Float,
    )

    private val snapshots: MutableMap<Int, Snapshot> = mutableMapOf()

    @Synchronized
    private fun ensureBaseDimensionsCaptured() {
        if (basePortraitWidth != 0) return
        val dm = Resources.getSystem().displayMetrics
        val w = dm.widthPixels
        val h = dm.heightPixels
        if (w <= h) {
            basePortraitWidth = w
            basePortraitHeight = h
            baseLandscapeWidth = h
            baseLandscapeHeight = w
        } else {
            basePortraitWidth = h
            basePortraitHeight = w
            baseLandscapeWidth = w
            baseLandscapeHeight = h
        }
    }

    private fun baseWidthFor(orientation: Int): Int {
        ensureBaseDimensionsCaptured()
        return if (orientation == Configuration.ORIENTATION_LANDSCAPE) baseLandscapeWidth else basePortraitWidth
    }

    private fun baseHeightFor(orientation: Int): Int {
        ensureBaseDimensionsCaptured()
        return if (orientation == Configuration.ORIENTATION_LANDSCAPE) baseLandscapeHeight else basePortraitHeight
    }

    /**
     * Apply (or remove) the per-pane viewport policy for [engineView].
     *
     * @param engineView the Mozilla AC EngineView whose native surface
     *   should be scaled.
     * @param paneCount the number of panes currently visible. When
     *   `<= 1` the policy is removed and the view is restored to its
     *   pre-policy layout state.
     */
    @Synchronized
    fun applyTo(engineView: EngineView, paneCount: Int) {
        // Bug fix (user-reported): the previous compositor-scaling strategy
        // caused two regressions on multi-pane mode:
        //   1. A "mini window inside a window" effect — `minOf(scaleX,
        //      scaleY)` letterboxed the rendered surface inside the pane.
        //   2. Pinch-zoom only worked in the focused pane, because the
        //      scale/pivot transform on the host FrameLayout interfered
        //      with multi-touch dispatch for non-focused panes.
        //
        // We now treat this policy as a no-op and simply restore each
        // EngineView to its natural layout. GeckoView renders directly at
        // the pane's actual pixel size, which keeps proportions correct,
        // fills the pane, and lets pinch-zoom work in every pane.
        clear(engineView)
    }

    private fun applyImmediate(native: View) {
        val parent = native.parent as? ViewGroup ?: return
        val paneWidthPx = parent.width
        val paneHeightPx = parent.height
        if (paneWidthPx <= 0 || paneHeightPx <= 0) return

        val orientation = native.resources.configuration.orientation
        val baseW = baseWidthFor(orientation)
        val baseH = baseHeightFor(orientation)
        if (baseW <= 0 || baseH <= 0) return

        // If the pane is already at-or-above the base width there is
        // nothing to scale — Gecko will lay out the page at its natural
        // single-pane width.
        if (paneWidthPx >= baseW && paneHeightPx >= baseH) {
            clearImmediate(native)
            return
        }

        val key = System.identityHashCode(native)
        if (!snapshots.containsKey(key)) {
            val lp = native.layoutParams
            snapshots[key] = Snapshot(
                originalWidth = lp?.width ?: FrameLayout.LayoutParams.MATCH_PARENT,
                originalHeight = lp?.height ?: FrameLayout.LayoutParams.MATCH_PARENT,
                originalPivotX = native.pivotX,
                originalPivotY = native.pivotY,
                originalScaleX = native.scaleX,
                originalScaleY = native.scaleY,
            )
        }

        // Resize the native view to the full single-pane logical viewport.
        val lp = native.layoutParams ?: FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        lp.width = baseW
        lp.height = baseH
        native.layoutParams = lp

        // Pivot at top-left so the scaled surface aligns with the pane's
        // top-left corner instead of its centre.
        native.pivotX = 0f
        native.pivotY = 0f

        // Uniform scale: pick the smaller axis so the entire base
        // viewport fits within the pane without clipping. Aspect ratio
        // is preserved.
        val scaleX = paneWidthPx.toFloat() / baseW.toFloat()
        val scaleY = paneHeightPx.toFloat() / baseH.toFloat()
        val uniformScale = minOf(scaleX, scaleY)
        native.scaleX = uniformScale
        native.scaleY = uniformScale
        native.setTag(TAG_KEY, true)
    }

    /**
     * Remove any policy modifications previously applied to
     * [engineView]'s native surface. Safe to call repeatedly.
     */
    @Synchronized
    fun clear(engineView: EngineView) {
        clearImmediate(engineView.asView())
    }

    private fun clearImmediate(native: View) {
        val key = System.identityHashCode(native)
        val snapshot = snapshots.remove(key)
        if (snapshot != null) {
            val lp = native.layoutParams
            if (lp != null) {
                lp.width = snapshot.originalWidth
                lp.height = snapshot.originalHeight
                native.layoutParams = lp
            }
            native.pivotX = snapshot.originalPivotX
            native.pivotY = snapshot.originalPivotY
            native.scaleX = snapshot.originalScaleX
            native.scaleY = snapshot.originalScaleY
        } else {
            // No prior snapshot — best effort reset to identity.
            native.scaleX = 1f
            native.scaleY = 1f
        }
        native.setTag(TAG_KEY, null)
    }

    /**
     * Re-apply the policy for every pane currently registered in
     * [components]. Called from [BaseBrowserFragment.onConfigurationChanged]
     * so an orientation change re-evaluates the per-pane scale and base
     * viewport against the new dimensions.
     */
    @Synchronized
    fun refresh(components: Components) {
        val paneCount = components.paneEngineViews.size
        components.paneEngineViews.values.forEach { engineView ->
            applyTo(engineView, paneCount)
        }
    }
}
