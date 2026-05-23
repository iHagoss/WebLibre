/*
 * WebLibre Cross-Pane Coordinator — background script.
 *
 * Runs once globally inside the shared GeckoRuntime. Maintains a registry of
 * connected content-script ports keyed by tab id. Routes register/ping/pong
 * and targeted send messages between panes.
 *
 * IMPORTANT:
 *   - This script never touches DOM. DOM remains isolated per content script.
 *   - It only forwards messages between extension ports.
 *   - One background instance sees connections from all visible panes because
 *     all panes share one GeckoRuntime / one Engine / one BrowserStore.
 */

"use strict";

const PORT_NAME = "cross-pane-coordinator";

// Map<tabId:string, browser.runtime.Port>
const portsByTabId = new Map();

function log(...args) {
  try {
    console.log("[cross-pane-coordinator/bg]", ...args);
  } catch (_) {
    // ignore
  }
}

function broadcast(message, exceptTabId) {
  for (const [tabId, p] of portsByTabId.entries()) {
    if (tabId === exceptTabId) continue;
    try {
      p.postMessage(message);
    } catch (e) {
      log("broadcast post failed for", tabId, e);
    }
  }
}

function sendTo(targetTabId, message) {
  const p = portsByTabId.get(targetTabId);
  if (!p) {
    log("sendTo: no port for", targetTabId);
    return false;
  }
  try {
    p.postMessage(message);
    return true;
  } catch (e) {
    log("sendTo failed for", targetTabId, e);
    return false;
  }
}

function resolveTabId(port, providedTabId) {
  if (typeof providedTabId === "string" && providedTabId.length > 0) {
    return providedTabId;
  }
  try {
    const senderTabId = port && port.sender && port.sender.tab && port.sender.tab.id;
    if (senderTabId != null) {
      return "gecko-tab-" + String(senderTabId);
    }
  } catch (_) {
    // ignore
  }
  return "anon-" + Math.random().toString(36).slice(2, 10);
}

browser.runtime.onConnect.addListener((port) => {
  if (port.name !== PORT_NAME) {
    return;
  }

  let boundTabId = null;

  port.onMessage.addListener((msg) => {
    if (!msg || typeof msg !== "object") return;

    switch (msg.type) {
      case "register": {
        const tabId = resolveTabId(port, msg.tabId);
        boundTabId = tabId;
        portsByTabId.set(tabId, port);
        log("register", tabId, "total=", portsByTabId.size);
        try {
          port.postMessage({ type: "registered", tabId });
        } catch (_) {
          // ignore
        }
        broadcast({ type: "peer-joined", tabId }, tabId);
        break;
      }
      case "ping": {
        const fromTabId = msg.tabId || boundTabId;
        if (!fromTabId) return;
        log("ping from", fromTabId);
        try {
          port.postMessage({ type: "pong", fromTabId });
        } catch (_) {
          // ignore
        }
        break;
      }
      case "send": {
        const targetTabId = msg.targetTabId;
        if (!targetTabId) return;
        const ok = sendTo(targetTabId, {
          type: "message",
          fromTabId: boundTabId,
          payload: msg.payload,
        });
        if (!ok) {
          try {
            port.postMessage({
              type: "send-failed",
              targetTabId,
            });
          } catch (_) {
            // ignore
          }
        }
        break;
      }
      default:
        // unknown message type, ignore
        break;
    }
  });

  port.onDisconnect.addListener(() => {
    if (boundTabId && portsByTabId.get(boundTabId) === port) {
      portsByTabId.delete(boundTabId);
      log("disconnect", boundTabId, "remaining=", portsByTabId.size);
      broadcast({ type: "peer-left", tabId: boundTabId }, boundTabId);
    }
  });
});

log("background loaded");
