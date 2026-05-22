/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Smoke tests for [MultiPaneRegistry].
 *
 * These tests intentionally avoid any Android framework calls so they can run
 * via the existing JUnit5 unit-test configuration in
 * `packages/flutter_mozilla_components/android/build.gradle`. No Robolectric,
 * no Activity, no FragmentManager.
 *
 * `MultiPaneRegistry` is a Kotlin `object` (singleton) so each test must
 * reset state via [MultiPaneRegistry.clearForTesting] in `@BeforeTest`.
 */
internal class MultiPaneRegistryTest {

    @BeforeTest
    fun resetRegistry() {
        MultiPaneRegistry.clearForTesting()
    }

    @Test
    fun registerPlatformView_storesContainerMapping() {
        MultiPaneRegistry.registerPlatformView(platformViewId = 1, containerViewId = 1001)
        MultiPaneRegistry.registerPlatformView(platformViewId = 2, containerViewId = 1002)

        assertEquals(1001, MultiPaneRegistry.getContainerViewId(1))
        assertEquals(1002, MultiPaneRegistry.getContainerViewId(2))
        assertNull(MultiPaneRegistry.getContainerViewId(99))
    }

    @Test
    fun unregisterPlatformView_removesMapping() {
        MultiPaneRegistry.registerPlatformView(platformViewId = 1, containerViewId = 1001)
        MultiPaneRegistry.unregisterPlatformView(1)

        assertNull(MultiPaneRegistry.getContainerViewId(1))
    }

    @Test
    fun unregisterPlatformView_doesNotAffectOtherEntries() {
        MultiPaneRegistry.registerPlatformView(platformViewId = 1, containerViewId = 1001)
        MultiPaneRegistry.registerPlatformView(platformViewId = 2, containerViewId = 1002)

        MultiPaneRegistry.unregisterPlatformView(1)

        assertNull(MultiPaneRegistry.getContainerViewId(1))
        assertEquals(1002, MultiPaneRegistry.getContainerViewId(2))
    }

    @Test
    fun bindPane_storesTabIdForPane() {
        MultiPaneRegistry.bindPane(paneId = "pane-0", tabId = "tab-a")
        MultiPaneRegistry.bindPane(paneId = "pane-1", tabId = "tab-b")

        assertEquals("tab-a", MultiPaneRegistry.getTabIdForPane("pane-0"))
        assertEquals("tab-b", MultiPaneRegistry.getTabIdForPane("pane-1"))
        assertNull(MultiPaneRegistry.getTabIdForPane("pane-99"))
    }

    @Test
    fun bindPane_overwritesPreviousTabForSamePane() {
        MultiPaneRegistry.bindPane(paneId = "pane-0", tabId = "tab-a")
        MultiPaneRegistry.bindPane(paneId = "pane-0", tabId = "tab-b")

        assertEquals("tab-b", MultiPaneRegistry.getTabIdForPane("pane-0"))
    }

    @Test
    fun setFocusedPane_updatesFocusedQueries() {
        MultiPaneRegistry.bindPane(paneId = "pane-0", tabId = "tab-a")
        MultiPaneRegistry.bindPane(paneId = "pane-1", tabId = "tab-b")

        MultiPaneRegistry.setFocusedPane("pane-1")

        assertEquals("pane-1", MultiPaneRegistry.getFocusedPaneId())
        assertTrue(MultiPaneRegistry.isFocusedPane("pane-1"))
        assertFalse(MultiPaneRegistry.isFocusedPane("pane-0"))
    }

    @Test
    fun setFocusedPane_canSwitchBetweenPanes() {
        MultiPaneRegistry.setFocusedPane("pane-0")
        assertTrue(MultiPaneRegistry.isFocusedPane("pane-0"))

        MultiPaneRegistry.setFocusedPane("pane-2")
        assertFalse(MultiPaneRegistry.isFocusedPane("pane-0"))
        assertTrue(MultiPaneRegistry.isFocusedPane("pane-2"))
    }

    @Test
    fun isFocusedPane_isFalseWhenNoPaneFocused() {
        assertNull(MultiPaneRegistry.getFocusedPaneId())
        assertFalse(MultiPaneRegistry.isFocusedPane("pane-0"))
    }

    @Test
    fun clearForTesting_resetsAllState() {
        MultiPaneRegistry.registerPlatformView(platformViewId = 1, containerViewId = 1001)
        MultiPaneRegistry.bindPane(paneId = "pane-0", tabId = "tab-a")
        MultiPaneRegistry.setFocusedPane("pane-0")

        MultiPaneRegistry.clearForTesting()

        assertNull(MultiPaneRegistry.getContainerViewId(1))
        assertNull(MultiPaneRegistry.getTabIdForPane("pane-0"))
        assertNull(MultiPaneRegistry.getFocusedPaneId())
    }
}
