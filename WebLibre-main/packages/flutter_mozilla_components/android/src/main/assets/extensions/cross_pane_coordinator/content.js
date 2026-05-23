/*
 * WebLibre Cross-Pane Coordinator — content script.
 *
 * Runs in each pane/tab. Opens one named extension port to the background
 * script, registers a tab identifier, and emits a periodic ping. Logs
 * pong / peer / broadcast events to the page console for debugging.
 *
 * IMPORTANT:
 *   - This script never reads or mutates DOM of other tabs.
 *   - Communication happens exclusively over the extension port.
 */

"use strict";

(function () {
  const PORT_NAME = "cross-pane-coordinator";
  const PING_INTERVAL_MS = 10_000;

  function makeLocalTabId() {
    try {
      const url = new URL(window.location.href);
      const host = url.hostname || "blank";
      return (
        "pane-tab-" +
        host +
        "-" +
        Math.random().toString(36).slice(2, 10)
      );
    } catch (_) {
      return "pane-tab-" + Math.random().toString(36).slice(2, 10);
    }
  }

  function log(...args) {
    try {
      console.log("[cross-pane-coordinator]", ...args);
    } catch (_) {
      // ignore
    }
  }

  // Allow the page or app to inject an explicit tab id on window before this
  // script runs. Falls back to a random local id otherwise.
  const tabId =
    (typeof window !== "undefined" &&
      typeof window.__weblibreTabId === "string" &&
      window.__weblibreTabId) ||
    makeLocalTabId();

  let port = null;
  let pingTimer = null;
  let stopped = false;

  function startPing() {
    if (pingTimer != null) return;
    pingTimer = setInterval(() => {
      if (!port) return;
      try {
        port.postMessage({ type: "ping", tabId });
      } catch (e) {
        log("ping failed", e);
      }
    }, PING_INTERVAL_MS);
  }

  function stopPing() {
    if (pingTimer != null) {
      clearInterval(pingTimer);
      pingTimer = null;
    }
  }

  function connect() {
    if (stopped) return;
    try {
      port = browser.runtime.connect({ name: PORT_NAME });
    } catch (e) {
      log("connect failed", e);
      return;
    }

    port.onMessage.addListener((msg) => {
      if (!msg || typeof msg !== "object") return;
      switch (msg.type) {
        case "registered":
          log("registered as", msg.tabId);
          break;
        case "pong":
          log("pong from", msg.fromTabId);
          break;
        case "peer-joined":
          log("peer joined", msg.tabId);
          break;
        case "peer-left":
          log("peer left", msg.tabId);
          break;
        case "message":
          log("message from", msg.fromTabId, msg.payload);
          break;
        case "send-failed":
          log("send failed to", msg.targetTabId);
          break;
        default:
          break;
      }
    });

    port.onDisconnect.addListener(() => {
      log("disconnected");
      stopPing();
      port = null;
    });

    try {
      port.postMessage({ type: "register", tabId });
    } catch (e) {
      log("register failed", e);
    }
    startPing();
  }

  window.addEventListener(
    "pagehide",
    () => {
      stopped = true;
      stopPing();
      try {
        port && port.disconnect();
      } catch (_) {
        // ignore
      }
    },
    { once: true }
  );

  connect();
})();
