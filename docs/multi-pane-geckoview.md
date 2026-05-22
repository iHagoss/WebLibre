# Multi-Pane GeckoView in WebLibre

Implementation notes and known limitations for the WebLibre 1/2/3/4-pane
split browsing feature. This is the engineering companion to the
`Multi-Pane GeckoView Browsing` section of the top-level `README.md`.

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│ Flutter (apps/weblibre)                                           │
│                                                                   │
│   PaneModeSwitcher ──► paneControllerProvider (Riverpod)          │
│                              │                                    │
│                              ▼                                    │
│            PaneState { mode, paneTabIds[4], focusedPaneIndex }    │
│                              │                                    │
│                              ▼                                    │
│         MultiPaneBrowserView  ──►  one GeckoView per visible pane │
│                                       (paneId, tabId, focused)    │
└──────────────────────────────┬────────────────────────────────────┘
                               │ Pigeon (showNativeFragmentForPane)
                               ▼
┌───────────────────────────────────────────────────────────────────┐
│ Android (packages/flutter_mozilla_components)                     │
│                                                                   │
│   GeckoViewFactory ──► GeckoPlatformView (unique container id)    │
│        │                                                          │
│        ▼                                                          │
│   MultiPaneRegistry  (platformViewId↔containerViewId, paneId↔tab) │
│        │                                                          │
│        ▼                                                          │
│   GeckoBrowserApiImpl.showNativeFragmentForPane(...)              │
│        │                                                          │
│        ▼                                                          │
│   FragmentManager: BrowserFragment(paneId, sessionId=tabId)       │
│        │                                                          │
│        ▼                                                          │
│   Components.paneEngineViews[paneId] = EngineView                 │
│        │                                                          │
│        ▼                                                          │
│   Android Components BrowserStore  ──►  one EngineSession per tab │
│        │                                                          │
│        ▼                                                          │
│   EngineProvider.getOrCreateRuntime()  ──►  ONE GeckoRuntime      │
└───────────────────────────────────────────────────────────────────┘
```

Key invariants:

1. **Exactly one `GeckoRuntime`** lives at any time, owned by `EngineProvider`.
2. **Exactly one `Engine`** is created via `EngineProvider.createEngine(...)`.
3. **`BrowserStore`** is the single runtime source of truth for tabs/sessions.
4. **`TabRepository`** (Dart) is the single persistence source of truth for
   tab metadata, isolation context IDs, and container assignment.
5. **`MultiPaneRegistry`** holds *attachment-only* state — never tab data.
6. **Pane fragments** attach existing sessions; disposing a pane never closes
   its tab.

## Why DOM cannot be shared across panes

GeckoView/Gecko intentionally isolates each `EngineSession` so that:

- Each tab has its own content process / JS realm.
- DOM, `window`, `document`, IndexedDB, service workers, etc., are scoped to
  the tab's origin × contextual identity.
- Extensions can observe and message *across* tabs only via the WebExtension
  background/content-script port boundary.

WebLibre does **not** attempt to bridge DOM across panes. Instead, the bundled
`cross-pane-coordinator` extension exposes a lightweight message bus so
pages/extensions can opt-in to cross-pane coordination without breaking the
sandbox.

## Known limitations

- **Memory**: each visible pane spins up an `EngineView` (and the underlying
  Gecko content process may be retained for active tabs). 4-pane mode roughly
  quadruples per-frame compositor work and resident memory vs. single pane.
  On low-memory devices, consider suspending hidden panes (backlog P2).
- **Global features**: keyboard insets, viewport scroll-away toolbars, and
  `SessionFeature.back()` must follow the focused pane only — not all panes
  at once. This is enforced in `BaseBrowserFragment` by gating global feature
  starts on `paneId == focused || legacy single-pane`.
- **Cookie / storage isolation**: depends on GeckoView's contextual identity
  + private mode support. Seeded pane tabs use `TabMode.newIsolated()` with
  unique `iso1_<uuid>` context IDs, but the strength of isolation is bounded
  by Gecko itself.
- **Fragment commits**: `commitNow` is avoided if the FragmentManager state
  has been saved. The pane-aware API returns `false` so Dart retries on the
  next frame.
- **Rotation**: existing `configChanges` in `AndroidManifest.xml` covers
  orientation/screen size — sessions are not destroyed by rotation.

## Test matrix


| # | Scenario                                       | Portrait | Landscape |
|---|------------------------------------------------|----------|-----------|
| 1 | First launch shows pane 0 = example.com        | ✅       | ✅        |
| 2 | Switch to 2 panes → 2nd pane = mozilla.org     | ✅       | ✅        |
| 3 | Switch to 3 panes → 3rd pane = developer.a.c   | ✅       | ✅        |
| 4 | Switch to 4 panes → 4th pane = wikipedia.org   | ✅       | ✅        |
| 5 | Independent scroll per pane                    | ✅       | ✅        |
| 6 | Soft keyboard in one pane does not break others| ✅       | ✅        |
| 7 | Rotate device — sessions remain loaded         | ✅       | ✅        |
| 8 | 4 → 1 → 4 — no reload, no new tabs             | ✅       | ✅        |
| 9 | Extension ping/pong logs from all panes        | ✅       | ✅        |
|10 | Pane switcher avoids gesture pill / cutout     | ✅       | ✅        |
