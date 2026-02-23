// kwin-auto-tile: Auto-tiling KWin Script for KDE Plasma 6
// Distributes windows in equal-width columns per monitor/desktop.

// ─── Section 1: Configuration ───

var config = {
    enabled: readConfig("enabled", true),
    maxVisible: readConfig("maxVisible", 4),
    debounceMs: readConfig("debounceMs", 300),
    maxEventsPerSecond: readConfig("maxEventsPerSecond", 20),
    gapSize: readConfig("gapSize", 8),
    respectMinimized: readConfig("respectMinimized", true),
    filterByClass: []
};

(function parseFilterByClass() {
    var raw = readConfig("filterByClass", "");
    if (typeof raw === "string" && raw.length > 0) {
        // Support both comma-separated and newline-separated formats
        config.filterByClass = raw.split(/[,\n]/)
            .map(function(s) { return s.trim().toLowerCase(); })
            .filter(function(s) { return s.length > 0; });
    }
})();

// ─── Section 2: State ───

var knownWindowIds = {};       // id -> true (tracks connected windows)
var prevLayoutKeys = {};       // "desktopId:outputName" -> layout cache key
var excludedWindowIds = {};    // id -> true (user-excluded via context menu)
var windowInsertOrder = [];    // window ids in insertion order for stable layout

// Rate limiter state
var eventCount = 0;
var eventWindowStart = 0;

// Debounce state: timestamp-based via recursive callDBus polling
var debounceScheduledAt = 0;

// ─── Section 3: Window Filtering ───

function isTileable(window) {
    if (!window) {
        return false;
    }

    // Guard against accessing properties on destroyed windows
    try {
        var isNormal = window.normalWindow;
    } catch (e) {
        return false;
    }

    if (!isNormal) {
        return false;
    }

    // Reject special window types
    if (window.dialog || window.splash || window.utility ||
        window.dock || window.desktopWindow || window.popupMenu ||
        window.tooltip || window.notification || window.criticalNotification ||
        window.appletPopup || window.onScreenDisplay) {
        return false;
    }

    // Reject minimized windows if configured
    if (config.respectMinimized && window.minimized) {
        return false;
    }

    // Reject fullscreen windows
    if (window.fullScreen) {
        return false;
    }

    // Reject user-excluded windows
    if (excludedWindowIds[window.internalId]) {
        return false;
    }

    // Check class filter
    if (config.filterByClass.length > 0) {
        var windowClass = (window.resourceClass || "").toLowerCase();
        var windowName = (window.resourceName || "").toLowerCase();
        for (var i = 0; i < config.filterByClass.length; i++) {
            var filter = config.filterByClass[i];
            if (windowClass === filter || windowName === filter) {
                return false;
            }
        }
    }

    // Reject windows that cannot be resized
    if (!window.resizeable) {
        return false;
    }

    return true;
}

// ─── Section 4: Window Grouping ───

function getDesktopKey(desktop, output) {
    var desktopId = desktop ? desktop.id : "all";
    var outputName = output ? output.name : "unknown";
    return desktopId + ":" + outputName;
}

function getWindowGroups() {
    var groups = {};
    var allWindows = workspace.windowList();
    var groupKey;

    for (var i = 0; i < allWindows.length; i++) {
        var win = allWindows[i];
        if (!isTileable(win)) {
            continue;
        }

        var output = win.output;
        if (!output) {
            continue;
        }

        if (win.onAllDesktops) {
            var currentDesktop = workspace.currentDesktop;
            groupKey = getDesktopKey(currentDesktop, output);
            if (!groups[groupKey]) {
                groups[groupKey] = { desktop: currentDesktop, output: output, windows: [] };
            }
            groups[groupKey].windows.push(win);
        } else {
            var desktops = win.desktops;
            for (var d = 0; d < desktops.length; d++) {
                var desktop = desktops[d];
                groupKey = getDesktopKey(desktop, output);
                if (!groups[groupKey]) {
                    groups[groupKey] = { desktop: desktop, output: output, windows: [] };
                }
                groups[groupKey].windows.push(win);
            }
        }
    }

    return groups;
}

// ─── Section 5: Redistribution Algorithm ───

function sortByInsertOrder(windows) {
    var orderMap = {};
    for (var i = 0; i < windowInsertOrder.length; i++) {
        orderMap[windowInsertOrder[i]] = i;
    }
    return windows.slice().sort(function(a, b) {
        var idxA = (a.internalId in orderMap) ? orderMap[a.internalId] : 999999;
        var idxB = (b.internalId in orderMap) ? orderMap[b.internalId] : 999999;
        return idxA - idxB;
    });
}

function redistributeGroup(group) {
    var windows = sortByInsertOrder(group.windows);
    var count = windows.length;

    if (count === 0) {
        return;
    }

    var key = getDesktopKey(group.desktop, group.output);

    // Cache includes window IDs so moves/swaps invalidate it
    var windowIds = windows.map(function(w) { return w.internalId; }).join(",");
    var layoutKey = count + ":" + config.maxVisible + ":" + config.gapSize + ":" + windowIds;
    if (prevLayoutKeys[key] === layoutKey) {
        return;
    }
    prevLayoutKeys[key] = layoutKey;

    // Get available area (respects panels, docks, etc.)
    var area = workspace.clientArea(
        KWin.PlacementArea,
        group.output,
        group.desktop
    );

    if (!area || area.width <= 0 || area.height <= 0) {
        return;
    }

    var gap = config.gapSize;
    var maxVis = config.maxVisible;

    // Always calculate width based on maxVisible (like niri behavior)
    var totalGapsH = gap * (maxVis + 1);
    var colWidth = Math.floor((area.width - totalGapsH) / maxVis);
    var colHeight = area.height - (gap * 2);

    // Position each window (up to maxVisible)
    var visibleCount = Math.min(count, maxVis);
    for (var i = 0; i < visibleCount; i++) {
        var win = windows[i];
        var x = area.x + gap + (i * (colWidth + gap));
        var y = area.y + gap;

        win.frameGeometry = Qt.rect(x, y, colWidth, colHeight);
    }

    // Move overflow windows off-screen to the right (they remain accessible via task switcher)
    for (var j = visibleCount; j < count; j++) {
        var overflowWin = windows[j];
        var offX = area.x + area.width + gap;
        overflowWin.frameGeometry = Qt.rect(offX, area.y + gap, colWidth, colHeight);
    }
}

function redistribute() {
    if (!config.enabled) {
        return;
    }

    var groups = getWindowGroups();
    for (var key in groups) {
        if (groups.hasOwnProperty(key)) {
            redistributeGroup(groups[key]);
        }
    }
}

// ─── Section 6: Debounce & Rate Limiting ───

function debouncePoll(scheduledAt) {
    if (scheduledAt !== debounceScheduledAt) {
        return;
    }

    var elapsed = Date.now() - scheduledAt;
    if (elapsed < config.debounceMs) {
        // Not enough time has passed, poll again
        callDBus(
            "org.kde.KWin", "/KWin", "org.kde.KWin", "currentDesktop",
            function() { debouncePoll(scheduledAt); }
        );
    } else {
        redistribute();
    }
}

function scheduleRedistribute() {
    if (!config.enabled) {
        return;
    }

    var now = Date.now();

    // Rate limiter: sliding window
    if (now - eventWindowStart > 1000) {
        eventWindowStart = now;
        eventCount = 0;
    }
    eventCount++;
    if (eventCount > config.maxEventsPerSecond) {
        return;
    }

    // Reset debounce: new timestamp supersedes any pending poll
    debounceScheduledAt = now;
    var scheduledAt = debounceScheduledAt;

    callDBus(
        "org.kde.KWin", "/KWin", "org.kde.KWin", "currentDesktop",
        function() { debouncePoll(scheduledAt); }
    );
}

function invalidateCachesAndRedistribute() {
    prevLayoutKeys = {};
    scheduleRedistribute();
}

// ─── Section 7: Event Handlers ───

function connectWindowSignals(window) {
    window.minimizedChanged.connect(function() {
        invalidateCachesAndRedistribute();
    });

    window.fullScreenChanged.connect(function() {
        invalidateCachesAndRedistribute();
    });

    window.desktopsChanged.connect(function() {
        invalidateCachesAndRedistribute();
    });

    window.outputChanged.connect(function() {
        invalidateCachesAndRedistribute();
    });
}

function onWindowAdded(window) {
    if (!window) {
        return;
    }

    var id = window.internalId;

    // Track insertion order (only for tileable windows)
    if (isTileable(window) && windowInsertOrder.indexOf(id) === -1) {
        windowInsertOrder.push(id);
    }

    // Connect per-window signals (only once)
    if (!knownWindowIds[id]) {
        knownWindowIds[id] = true;
        connectWindowSignals(window);
    }

    invalidateCachesAndRedistribute();
}

function onWindowRemoved(window) {
    if (!window) {
        return;
    }

    var id = window.internalId;
    delete knownWindowIds[id];
    delete excludedWindowIds[id];

    // Remove from insert order
    var idx = windowInsertOrder.indexOf(id);
    if (idx !== -1) {
        windowInsertOrder.splice(idx, 1);
    }

    invalidateCachesAndRedistribute();
}

// ─── Section 8: Keyboard Shortcuts ───

function registerShortcuts() {
    registerShortcut(
        "AutoTile: 1 Column",
        "Auto Tile: Set 1 column",
        "Meta+Ctrl+1",
        function() {
            config.maxVisible = 1;
            invalidateCachesAndRedistribute();
        }
    );

    registerShortcut(
        "AutoTile: 2 Columns",
        "Auto Tile: Set 2 columns",
        "Meta+Ctrl+2",
        function() {
            config.maxVisible = 2;
            invalidateCachesAndRedistribute();
        }
    );

    registerShortcut(
        "AutoTile: 3 Columns",
        "Auto Tile: Set 3 columns",
        "Meta+Ctrl+3",
        function() {
            config.maxVisible = 3;
            invalidateCachesAndRedistribute();
        }
    );

    registerShortcut(
        "AutoTile: 4 Columns",
        "Auto Tile: Set 4 columns",
        "Meta+Ctrl+4",
        function() {
            config.maxVisible = 4;
            invalidateCachesAndRedistribute();
        }
    );

    registerShortcut(
        "AutoTile: Re-tile",
        "Auto Tile: Force re-tile all windows",
        "Meta+Ctrl+T",
        function() {
            invalidateCachesAndRedistribute();
        }
    );
}

// ─── Section 9: Context Menu ───

function registerContextMenu() {
    registerUserActionsMenu(function(window) {
        var id = window.internalId;
        var isExcluded = !!excludedWindowIds[id];

        return {
            text: isExcluded ? "Include in Auto-Tile" : "Exclude from Auto-Tile",
            triggered: function() {
                if (isExcluded) {
                    delete excludedWindowIds[id];
                } else {
                    excludedWindowIds[id] = true;
                }
                invalidateCachesAndRedistribute();
            }
        };
    });
}

// ─── Section 10: Initialization ───

(function init() {
    if (!config.enabled) {
        return;
    }

    registerShortcuts();
    registerContextMenu();

    // Connect workspace-level signals
    workspace.windowAdded.connect(onWindowAdded);
    workspace.windowRemoved.connect(onWindowRemoved);
    workspace.currentDesktopChanged.connect(function() {
        invalidateCachesAndRedistribute();
    });

    // Screen/output changes: try both signal names for KWin 5/6 compat
    if (workspace.screensChanged) {
        workspace.screensChanged.connect(function() {
            invalidateCachesAndRedistribute();
        });
    }
    if (workspace.outputsChanged) {
        workspace.outputsChanged.connect(function() {
            invalidateCachesAndRedistribute();
        });
    }

    // Initialize with existing windows (only track tileable in insert order)
    var existingWindows = workspace.windowList();
    for (var i = 0; i < existingWindows.length; i++) {
        var win = existingWindows[i];
        var id = win.internalId;
        knownWindowIds[id] = true;
        if (isTileable(win)) {
            windowInsertOrder.push(id);
        }
        connectWindowSignals(win);
    }

    // Initial redistribution
    redistribute();
})();
