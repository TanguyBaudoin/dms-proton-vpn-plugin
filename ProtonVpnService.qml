pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "./ProtonVpnParsers.js" as VpnParsers

Item {
    id: root

    readonly property string pluginId: "protonVPNplugin"

    readonly property var defaults: ({
            vpnBinary: "protonvpn",
            refreshIntervalSec: 10,
            locationsCount: 0,
            connectStrategy: "fastest",
            defaultLocation: "",
            ipStack: "auto",
            autoRefreshLocations: true,
            autoConnectOnStartup: false,
            autoReconnectOnDrop: false,
            favoriteLocationIsos: [],
            bypassMultiRouteCheck: true
        })

    property string vpnBinary: defaults.vpnBinary
    property int refreshIntervalSec: defaults.refreshIntervalSec
    property int locationsCount: defaults.locationsCount
    property string connectStrategy: defaults.connectStrategy
    property string defaultLocation: defaults.defaultLocation
    property string ipStack: defaults.ipStack
    property bool autoRefreshLocations: defaults.autoRefreshLocations
    property bool autoConnectOnStartup: defaults.autoConnectOnStartup
    property bool autoReconnectOnDrop: defaults.autoReconnectOnDrop
    property var favoriteLocationIsos: defaults.favoriteLocationIsos
    property bool bypassMultiRouteCheck: defaults.bypassMultiRouteCheck
    property bool startupAutoConnectAttempted: false
    property bool suppressReconnectOnce: false
    property string lastConnectKind: ""
    property string lastConnectValue: ""
    property string pendingReconnectKind: ""
    property string pendingReconnectValue: ""
    property string pendingKillSwitchValue: ""
    property bool pendingKillSwitchReconnect: false
    property int pendingKillSwitchAttempts: 0

    property bool cliAvailable: false
    property string cliVersion: ""
    property bool commandRunning: false
    property string runningCommand: ""

    property bool isConnected: false
    property string statusSummary: VpnI18n.tr("status.unknown", "Unknown")
    property string connectedLocation: ""
    property string connectedMode: ""
    property string tunnelInterface: ""

    property string accountEmail: ""
    property string accountTier: ""
    property int maxDevices: 0
    property string subscriptionRenewDate: ""

    property string currentMode: ""
    property string currentProtocol: "auto"
    property string currentProtocolRaw: ""
    property string currentUpdateChannel: "release"
    property string dnsUpstream: ""
    property string socksHost: ""
    property int socksPort: 1080
    property string routingMode: ""
    property bool changeSystemDns: false
    readonly property string tunnelLogPath: "$HOME/.cache/Proton/VPN/logs"
    readonly property string controlSocketPath: ""

    property var locations: []
    property var citiesByCountry: ({})
    property var currentCities: []
    property bool citiesLoading: false
    property string selectedCountryIso: ""
    property string selectedCountryName: ""
    property string lastCitiesRaw: ""
    property double lastCitiesRefreshMs: 0
    property string lastError: ""
    property string lastStatusRaw: ""
    property string lastConfigRaw: ""
    property string lastLicenseRaw: ""
    property string lastCommandText: ""
    property int lastCommandExitCode: -1
    property string lastCommandOutput: ""
    property double lastCommandAtMs: 0
    property bool licenseRefreshInFlight: false
    property double licenseRefreshStartedAtMs: 0
    property var pollingSnapshot: ({
            status: false,
            metadata: false,
            locations: false
        })

    property double lastRefreshMs: 0
    property double lastLocationsRefreshMs: 0

    function t(key, fallback, params) {
        return VpnI18n.tr(key, fallback, params);
    }

    function asInt(value, fallback, minimum, maximum) {
        var parsed = parseInt(value, 10);
        if (isNaN(parsed)) {
            parsed = fallback;
        }
        if (minimum !== undefined && parsed < minimum) {
            parsed = minimum;
        }
        if (maximum !== undefined && parsed > maximum) {
            parsed = maximum;
        }
        return parsed;
    }

    function asBool(value, fallback) {
        if (value === undefined || value === null) {
            return fallback;
        }
        return !!value;
    }

    function normalizedChoice(value, fallback, allowedValues) {
        var cleaned = (value || fallback || "").toString().toLowerCase().trim();
        if (allowedValues.indexOf(cleaned) >= 0) {
            return cleaned;
        }
        return fallback;
    }

    function stripAnsi(text) {
        return (text || "").replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "").replace(/\x1b[@-_]/g, "");
    }

    function cleanOutput(text) {
        return stripAnsi(text || "").replace(/\r/g, "").trim();
    }

    function shellQuote(value) {
        const raw = (value || "").toString();
        return `'${raw.replace(/'/g, `'\\''`)}'`;
    }

    function normalizeFavoriteLocationIsos(value) {
        const list = [];
        const seen = ({});
        const source = Array.isArray(value) ? value : [];

        for (let i = 0; i < source.length; i++) {
            const iso = (source[i] || "").toString().trim().toUpperCase();
            if (!/^[A-Z]{2}$/.test(iso) || seen[iso]) {
                continue;
            }
            seen[iso] = true;
            list.push(iso);
        }

        return list;
    }

    function loadSettings() {
        const load = (key, defaultValue) => {
            const stored = PluginService.loadPluginData(pluginId, key);
            return stored !== undefined ? stored : defaultValue;
        };

        const legacyBinary = PluginService.loadPluginData(pluginId, "protonVpnBinary");
        vpnBinary = (load("vpnBinary", legacyBinary || defaults.vpnBinary) || defaults.vpnBinary).toString().trim();
        refreshIntervalSec = asInt(load("refreshIntervalSec", defaults.refreshIntervalSec), defaults.refreshIntervalSec, 3, 120);
        const rawLocationsCount = PluginService.loadPluginData(pluginId, "locationsCount");
        const migratedLocationsCountAll = asBool(load("migratedLocationsCountAll", false), false);
        const parsedLocationsCount = asInt(rawLocationsCount, defaults.locationsCount, 0, 500);
        if (parsedLocationsCount === 40) {
            locationsCount = 0;
            saveSetting("locationsCount", 0);
        } else {
            locationsCount = rawLocationsCount !== undefined ? parsedLocationsCount : defaults.locationsCount;
            if (!migratedLocationsCountAll) {
                saveSetting("migratedLocationsCountAll", true);
            }
        }
        connectStrategy = normalizedChoice(load("connectStrategy", defaults.connectStrategy), defaults.connectStrategy, ["fastest", "location"]);
        defaultLocation = (load("defaultLocation", defaults.defaultLocation) || "").toString().trim();
        ipStack = normalizedChoice(load("ipStack", defaults.ipStack), defaults.ipStack, ["auto", "ipv4", "ipv6"]);
        autoRefreshLocations = asBool(load("autoRefreshLocations", defaults.autoRefreshLocations), defaults.autoRefreshLocations);
        autoConnectOnStartup = asBool(load("autoConnectOnStartup", defaults.autoConnectOnStartup), defaults.autoConnectOnStartup);
        autoReconnectOnDrop = asBool(load("autoReconnectOnDrop", defaults.autoReconnectOnDrop), defaults.autoReconnectOnDrop);
        favoriteLocationIsos = normalizeFavoriteLocationIsos(load("favoriteLocationIsos", defaults.favoriteLocationIsos));
        bypassMultiRouteCheck = asBool(load("bypassMultiRouteCheck", defaults.bypassMultiRouteCheck), defaults.bypassMultiRouteCheck);
        lastConnectKind = (load("lastConnectKind", "") || "").toString().trim().toLowerCase();
        lastConnectValue = (load("lastConnectValue", "") || "").toString().trim();

        restartTimers();
        checkCliAvailability();
    }

    function saveSetting(key, value) {
        PluginService.savePluginData(pluginId, key, value);
    }

    function isFavoriteLocation(iso) {
        const normalizedIso = (iso || "").toString().trim().toUpperCase();
        if (!/^[A-Z]{2}$/.test(normalizedIso)) {
            return false;
        }
        return favoriteLocationIsos.indexOf(normalizedIso) >= 0;
    }

    function toggleFavoriteLocation(iso) {
        const normalizedIso = (iso || "").toString().trim().toUpperCase();
        if (!/^[A-Z]{2}$/.test(normalizedIso)) {
            return;
        }

        const next = favoriteLocationIsos.slice();
        const index = next.indexOf(normalizedIso);
        if (index >= 0) {
            next.splice(index, 1);
        } else {
            next.push(normalizedIso);
        }

        favoriteLocationIsos = normalizeFavoriteLocationIsos(next);
        saveSetting("favoriteLocationIsos", favoriteLocationIsos);
    }

    function restartTimers() {
        statusTimer.interval = refreshIntervalSec * 1000;
        metadataTimer.interval = Math.max(20, refreshIntervalSec * 3) * 1000;
        locationsTimer.interval = Math.max(45, refreshIntervalSec * 6) * 1000;

        if (!statusTimer.running) {
            statusTimer.start();
        }
        if (!metadataTimer.running) {
            metadataTimer.start();
        }
        locationsTimer.running = autoRefreshLocations;
        if (autoRefreshLocations) {
            locationsTimer.restart();
        }
    }

    function runCli(operation, args, callback, timeoutTicks) {
        const commandId = `${pluginId}.${operation}.${Date.now()}`;
        const command = [vpnBinary].concat(args || []);
        const timeoutValue = timeoutTicks !== undefined && timeoutTicks !== null ? timeoutTicks : 120;

        Proc.runCommand(commandId, command, (stdout, exitCode) => {
            callback(stdout || "", exitCode);
        }, timeoutValue);
    }

    function checkCliAvailability() {
        runCli("version", ["--version"], (stdout, exitCode) => {
            const clean = cleanOutput(stdout);
            cliAvailable = exitCode === 0;
            cliVersion = clean;

            if (!cliAvailable) {
                isConnected = false;
                statusSummary = t("status.cli_unavailable", "protonvpn unavailable");
                connectedLocation = "";
                connectedMode = "";
                tunnelInterface = "";
                lastError = clean || t("status.unable_run_cli", "Unable to run protonvpn");
                return;
            }

            lastError = "";
            refreshAll(true);
            maybeAutoConnectOnStartup();
        });
    }

    function parseStatus(stdout, exitCode) {
        const wasConnected = isConnected;
        const clean = cleanOutput(stdout);
        lastStatusRaw = clean;
        lastRefreshMs = Date.now();

        if (exitCode !== 0) {
            isConnected = false;
            statusSummary = clean || t("status.failed_read", "Failed to read VPN status");
            connectedLocation = "";
            connectedMode = "";
            tunnelInterface = "";
            lastError = statusSummary;
            maybeScheduleReconnect(wasConnected, isConnected);
            return;
        }

        cliAvailable = true;
        lastError = "";

        const parsed = VpnParsers.parseStatusOutput(clean);
        if (parsed.empty) {
            isConnected = false;
            statusSummary = t("status.no_output", "No status output");
            connectedLocation = "";
            connectedMode = "";
            tunnelInterface = "";
            maybeScheduleReconnect(wasConnected, isConnected);
            return;
        }

        if (parsed.disconnected) {
            isConnected = false;
            statusSummary = t("status.disconnected", "Disconnected");
            connectedLocation = "";
            connectedMode = "";
            tunnelInterface = "";
            maybeScheduleReconnect(wasConnected, isConnected);
            return;
        }

        if (parsed.connected) {
            isConnected = true;
            connectedLocation = parsed.connectedLocation || "";
            connectedMode = parsed.connectedMode || "";
            tunnelInterface = parsed.tunnelInterface || "";
            statusSummary = t("status.connected", "Connected ({location})", {
                location: connectedLocation || "-"
            });
            maybeScheduleReconnect(wasConnected, isConnected);
            return;
        }

        isConnected = !!parsed.isConnected;
        statusSummary = parsed.firstLine || t("status.unknown", "Unknown");
        if (!isConnected) {
            connectedLocation = "";
            connectedMode = "";
            tunnelInterface = "";
        }
        maybeScheduleReconnect(wasConnected, isConnected);
    }

    function parseLicense(stdout, exitCode) {
        const clean = cleanOutput(stdout);
        lastLicenseRaw = clean;
        if (exitCode !== 0) {
            return;
        }

        const parsed = VpnParsers.parseLicenseOutput(clean);
        if (parsed.accountEmail) {
            accountEmail = parsed.accountEmail;
        }
    }

    function parseConfig(stdout, exitCode) {
        const clean = cleanOutput(stdout);
        lastConfigRaw = clean;
        if (exitCode !== 0) {
            return;
        }

        const parsed = VpnParsers.parseConfigOutput(clean, {
            currentMode: currentMode,
            currentProtocol: currentProtocol,
            currentProtocolRaw: currentProtocolRaw,
            currentUpdateChannel: currentUpdateChannel,
            dnsUpstream: dnsUpstream,
            socksHost: socksHost,
            socksPort: socksPort,
            routingMode: routingMode
        });

        currentMode = parsed.currentMode;
        currentProtocolRaw = parsed.currentProtocolRaw;
        currentProtocol = parsed.currentProtocol;
        currentUpdateChannel = parsed.currentUpdateChannel;
        dnsUpstream = parsed.dnsUpstream;
        socksHost = parsed.socksHost;
        socksPort = parsed.socksPort;
        routingMode = parsed.routingMode;
        changeSystemDns = parsed.changeSystemDns;
    }

    function buildLocationHelpHint(messageText) {
        const text = (messageText || "").toString();
        if (/country code/i.test(text) || /country name/i.test(text)) {
            return t("hint.location_not_found", "Try refreshing countries and using the ISO code (e.g., US).", {});
        }
        return "";
    }

    function parseLocations(stdout, exitCode) {
        const clean = cleanOutput(stdout);
        if (exitCode !== 0) {
            if (clean) {
                lastError = clean;
            }
            return;
        }

        const parsed = VpnParsers.parseLocationsOutput(clean);
        if (parsed.parseFailed) {
            lastError = t("status.locations_parse_failed", "Could not parse countries list from CLI output");
        }
        locations = parsed.locations;
        lastLocationsRefreshMs = Date.now();
    }

    function parseCities(stdout, exitCode, countryIso) {
        const clean = cleanOutput(stdout);
        lastCitiesRaw = clean;

        if (exitCode !== 0) {
            if (clean) {
                lastError = clean;
            }
            return;
        }

        const parsed = VpnParsers.parseCitiesOutput(clean);
        if (parsed.parseFailed) {
            lastError = t("status.locations_parse_failed", "Could not parse cities list from CLI output");
            return;
        }

        const normalizedIso = (countryIso || "").toString().trim().toUpperCase();
        const nextCache = Object.assign({}, citiesByCountry);
        nextCache[normalizedIso] = parsed.cities;
        citiesByCountry = nextCache;

        if (selectedCountryIso === normalizedIso) {
            currentCities = parsed.cities;
        }
        lastCitiesRefreshMs = Date.now();
    }

    function refreshStatus() {
        if (!cliAvailable && !vpnBinary) {
            return;
        }

        runCli("status", ["status"], (stdout, exitCode) => {
            if (exitCode !== 0 && /not found|no such file|cannot execute/i.test(cleanOutput(stdout))) {
                cliAvailable = false;
                statusSummary = t("status.cli_unavailable", "protonvpn unavailable");
            }
            parseStatus(stdout, exitCode);
        });
    }

    function refreshConfig() {
        if (!cliAvailable) {
            return;
        }
        runCli("config", ["config", "list"], (stdout, exitCode) => {
            parseConfig(stdout, exitCode);
        });
    }

    function refreshLicense() {
        if (!cliAvailable) {
            return;
        }

        const now = Date.now();
        if (licenseRefreshInFlight) {
            if ((now - licenseRefreshStartedAtMs) < 30000) {
                return;
            }
            licenseRefreshInFlight = false;
            licenseRefreshStartedAtMs = 0;
        }

        licenseRefreshInFlight = true;
        licenseRefreshStartedAtMs = now;
        runCli("info", ["info"], (stdout, exitCode) => {
            parseLicense(stdout, exitCode);
            licenseRefreshInFlight = false;
            licenseRefreshStartedAtMs = 0;
        }, 200);
    }

    function refreshLocations() {
        if (!cliAvailable) {
            return;
        }

        const ranges = ["A-E", "F-J", "K-O", "P-T", "U-Z"];
        const collectedByIso = ({});
        let hadFailure = false;

        const refreshChunk = (index) => {
            if (index >= ranges.length) {
                const merged = Object.values(collectedByIso).sort((left, right) => {
                    return (left.country || "").localeCompare(right.country || "");
                });

                if (!merged.length && hadFailure) {
                    lastError = t("status.locations_parse_failed", "Could not parse countries list from CLI output");
                    return;
                }

                locations = merged;
                lastLocationsRefreshMs = Date.now();

                if (merged.length > 0) {
                    const selectedStillExists = merged.some(item => item.iso === selectedCountryIso);
                    if (!selectedStillExists) {
                        selectedCountryIso = merged[0].iso;
                        selectedCountryName = merged[0].country;
                    }
                    refreshCitiesForCountry(selectedCountryIso, false);
                }
                return;
            }

            const range = ranges[index];
            const chunkScript = `${shellQuote(vpnBinary)} countries list | awk 'NR > 2 && NF >= 2 { code=$NF; $NF=""; sub(/[[:space:]]+$/, "", $0); initial=toupper(substr($0, 1, 1)); if (initial ~ /^[${range}]$/) printf "%s|%s;", $0, code }'`;

            Proc.runCommand(`${pluginId}.countriesChunk.${range}.${Date.now()}`, ["sh", "-lc", chunkScript], (stdout, exitCode) => {
                const clean = cleanOutput(stdout);
                if (exitCode !== 0) {
                    hadFailure = true;
                    if (clean) {
                        lastError = clean;
                    }
                    refreshChunk(index + 1);
                    return;
                }

                const parsed = VpnParsers.parseLocationsOutput(clean);
                if (parsed.parseFailed) {
                    hadFailure = true;
                }

                for (let i = 0; i < parsed.locations.length; i++) {
                    const item = parsed.locations[i];
                    const iso = (item.iso || "").toString().trim().toUpperCase();
                    if (!iso) {
                        continue;
                    }
                    collectedByIso[iso] = item;
                }

                refreshChunk(index + 1);
            }, 120);
        };

        refreshChunk(0);
    }

    function selectCountry(iso, countryName) {
        const normalizedIso = (iso || "").toString().trim().toUpperCase();
        if (!/^[A-Z]{2}$/.test(normalizedIso)) {
            return;
        }

        selectedCountryIso = normalizedIso;
        selectedCountryName = (countryName || "").toString().trim();
        refreshCitiesForCountry(normalizedIso, false);
    }

    function refreshCitiesForCountry(countryIso, forceRefresh) {
        const normalizedIso = (countryIso || "").toString().trim().toUpperCase();
        if (!/^[A-Z]{2}$/.test(normalizedIso) || !cliAvailable) {
            return;
        }

        selectedCountryIso = normalizedIso;
        if (!forceRefresh && citiesByCountry[normalizedIso] !== undefined) {
            currentCities = citiesByCountry[normalizedIso] || [];
            return;
        }

        citiesLoading = true;
        runCli("cities", ["cities", "list", normalizedIso], (stdout, exitCode) => {
            parseCities(stdout, exitCode, normalizedIso);
            citiesLoading = false;
        }, 200);
    }

    function refreshAll(includeLocations) {
        refreshStatus();
        refreshConfig();
        refreshLicense();
        if (includeLocations || autoRefreshLocations || locations.length === 0) {
            refreshLocations();
        }
    }

    function suspendPolling() {
        pollingSnapshot = ({
                status: statusTimer.running,
                metadata: metadataTimer.running,
                locations: locationsTimer.running
            });

        statusTimer.stop();
        metadataTimer.stop();
        locationsTimer.stop();
    }

    function resumePolling() {
        if (pollingSnapshot.status) {
            statusTimer.start();
        }
        if (pollingSnapshot.metadata) {
            metadataTimer.start();
        }
        if (pollingSnapshot.locations && autoRefreshLocations) {
            locationsTimer.start();
        }
    }

    function recordLastCommand(args, exitCode, cleanOutputText) {
        const fullCommand = [vpnBinary].concat(args || []);
        const lines = (cleanOutputText || "").split("\n").map(line => line.trim()).filter(Boolean);

        lastCommandText = fullCommand.join(" ");
        lastCommandExitCode = exitCode;
        lastCommandOutput = lines.length ? lines[0] : "";
        lastCommandAtMs = Date.now();
    }

    function saveLastConnectTarget(kind, value) {
        const normalizedKind = (kind || "").toString().trim().toLowerCase();
        const normalizedValue = (value || "").toString().trim();
        if (!normalizedKind) {
            return;
        }

        lastConnectKind = normalizedKind;
        lastConnectValue = normalizedValue;
        saveSetting("lastConnectKind", lastConnectKind);
        saveSetting("lastConnectValue", lastConnectValue);
    }

    function extractServerId(locationText) {
        const text = (locationText || "").toString().trim();
        const match = text.match(/^([A-Za-z]{2}#\d+)\b/);
        return match ? match[1].toUpperCase() : "";
    }

    function queueReconnectFromCurrentSession() {
        const serverId = extractServerId(connectedLocation);
        if (serverId) {
            pendingReconnectKind = "server";
            pendingReconnectValue = serverId;
            return;
        }

        pendingReconnectKind = lastConnectKind;
        pendingReconnectValue = lastConnectValue;
    }

    function reconnectQueuedTarget() {
        const queuedKind = pendingReconnectKind;
        const queuedValue = pendingReconnectValue;
        pendingReconnectKind = "";
        pendingReconnectValue = "";

        if (queuedKind === "server" && queuedValue) {
            connectToServer(queuedValue);
            return;
        }

        reconnectLastTarget();
    }

    function clearPendingKillSwitchFlow() {
        pendingKillSwitchValue = "";
        pendingKillSwitchReconnect = false;
        pendingKillSwitchAttempts = 0;
        killSwitchApplyTimer.stop();
    }

    function applyPendingKillSwitchIfReady() {
        if (!pendingKillSwitchValue) {
            return;
        }

        if (commandRunning) {
            killSwitchApplyTimer.restart();
            return;
        }

        if (isConnected) {
            if (pendingKillSwitchAttempts <= 0) {
                ToastService.showError(t("app.title", "Proton VPN"), t("toast.killswitch_still_connected", "Still connected after disconnect request. Retry Kill Switch action."));
                clearPendingKillSwitchFlow();
                return;
            }

            pendingKillSwitchAttempts -= 1;
            killSwitchApplyTimer.restart();
            return;
        }

        const value = pendingKillSwitchValue;
        const reconnectAfterApply = pendingKillSwitchReconnect;
        clearPendingKillSwitchFlow();

        runAction("setKillSwitch", ["config", "set", "kill-switch", value], t("app.title", "Proton VPN"), t("toast.mode_set", "Kill switch set to {mode}", {
            mode: value
        }), {
            onSuccess: () => {
                if (reconnectAfterApply) {
                    Qt.callLater(() => {
                        reconnectQueuedTarget();
                    });
                }
            }
        });
    }

    function reconnectLastTarget() {
        if (!cliAvailable || commandRunning) {
            return;
        }

        if (lastConnectKind === "server" && lastConnectValue) {
            connectToServer(lastConnectValue);
            return;
        }

        if (lastConnectKind === "fastest") {
            connectFastest();
            return;
        }

        if (lastConnectKind === "country" && lastConnectValue) {
            connectToCountry(lastConnectValue);
            return;
        }

        if (lastConnectKind === "city" && lastConnectValue) {
            connectToCity(lastConnectValue);
            return;
        }

        if (lastConnectKind === "location" && lastConnectValue) {
            connectToLocation(lastConnectValue);
            return;
        }

        connectWithStrategy();
    }

    function connectWithStrategy() {
        if (connectStrategy === "location" && defaultLocation) {
            connectToLocation(defaultLocation);
            return;
        }
        connectFastest();
    }

    function maybeAutoConnectOnStartup() {
        if (startupAutoConnectAttempted || !autoConnectOnStartup || !cliAvailable || commandRunning || isConnected) {
            return;
        }
        startupAutoConnectAttempted = true;
        reconnectLastTarget();
    }

    function maybeScheduleReconnect(wasConnected, nowConnected) {
        if (nowConnected) {
            reconnectTimer.stop();
            suppressReconnectOnce = false;
            return;
        }

        if (suppressReconnectOnce) {
            suppressReconnectOnce = false;
            return;
        }

        if (!autoReconnectOnDrop || !wasConnected || !cliAvailable || commandRunning || reconnectTimer.running) {
            return;
        }

        ToastService.showInfo(t("app.title", "Proton VPN"), t("toast.reconnect_scheduled", "Connection dropped. Reconnecting..."));
        reconnectTimer.start();
    }

    function connectFastest() {
        saveLastConnectTarget("fastest", "");
        runAction("connectFastest", ["connect"], t("app.title", "Proton VPN"), t("toast.fastest_selected", "Fastest location selected"));
    }

    function connectToServer(serverId) {
        const normalizedServerId = (serverId || "").toString().trim().toUpperCase();
        if (!/^[A-Z]{2}#\d+$/.test(normalizedServerId)) {
            connectWithStrategy();
            return;
        }

        saveLastConnectTarget("server", normalizedServerId);
        runAction("connectServer", ["connect", normalizedServerId], t("app.title", "Proton VPN"), t("toast.connecting_to", "Connecting to {location}", {
            location: normalizedServerId
        }));
    }

    function connectToCountry(countryText) {
        const rawTarget = (countryText || "").toString().trim();
        if (!rawTarget) {
            ToastService.showError(t("app.title", "Proton VPN"), t("toast.location_empty", "Location is empty"));
            return;
        }

        const normalized = /^[A-Za-z]{2}$/.test(rawTarget) ? rawTarget.toUpperCase() : rawTarget;
        saveLastConnectTarget("country", normalized);
        runAction("connectCountry", ["connect", "--country", normalized], t("app.title", "Proton VPN"), t("toast.connecting_to", "Connecting to {location}", {
            location: normalized
        }));
    }

    function connectToCity(cityText) {
        const rawTarget = (cityText || "").toString().trim();
        if (!rawTarget) {
            ToastService.showError(t("app.title", "Proton VPN"), t("toast.location_empty", "Location is empty"));
            return;
        }

        saveLastConnectTarget("city", rawTarget);
        runAction("connectCity", ["connect", "--city", rawTarget], t("app.title", "Proton VPN"), t("toast.connecting_to", "Connecting to {location}", {
            location: rawTarget
        }));
    }

    function resolveLocationTarget(locationText) {
        const rawTarget = (locationText || "").toString().trim();
        if (!rawTarget) {
            return "";
        }

        const normalizedInput = rawTarget.toLowerCase();
        for (let i = 0; i < locations.length; i++) {
            const locationItem = locations[i];
            const iso = (locationItem.iso || "").toString().trim();
            const country = (locationItem.country || "").toString().trim();
            if (iso && iso.toLowerCase() === normalizedInput) {
                return iso;
            }
            if (country && country.toLowerCase() === normalizedInput) {
                return iso || rawTarget;
            }
        }
        return rawTarget;
    }

    function connectToLocation(locationText) {
        const rawTarget = (locationText || "").toString().trim();
        if (!rawTarget) {
            ToastService.showError(t("app.title", "Proton VPN"), t("toast.location_empty", "Location is empty"));
            return;
        }

        saveLastConnectTarget("location", rawTarget);

        const target = resolveLocationTarget(rawTarget);
        const useCountry = /^[A-Za-z]{2}$/.test(target) || locations.some(item => (item.country || "").toLowerCase() === rawTarget.toLowerCase());
        if (useCountry) {
            connectToCountry(target);
            return;
        }
        connectToCity(rawTarget);
    }

    function disconnect() {
        suppressReconnectOnce = true;
        runAction("disconnect", ["disconnect"], t("app.title", "Proton VPN"), t("toast.disconnect_requested", "Disconnect requested"));
    }

    function toggleConnection() {
        if (isConnected) {
            disconnect();
        } else {
            connectWithStrategy();
        }
    }

    function setMode(mode) {
        const value = (mode || "").toString().toLowerCase() === "tun" ? "standard" : "off";

        if (isConnected) {
            suppressReconnectOnce = true;
            queueReconnectFromCurrentSession();
            pendingKillSwitchValue = value;
            pendingKillSwitchReconnect = true;
            pendingKillSwitchAttempts = 6;
            runAction("disconnectForKillSwitch", ["disconnect"], t("app.title", "Proton VPN"), t("toast.disconnect_before_killswitch", "Disconnecting before changing Kill Switch"), {
                onSuccess: () => {
                    Qt.callLater(() => {
                        runCli("statusAfterKillSwitchDisconnect", ["status"], (stdout, exitCode) => {
                            parseStatus(stdout, exitCode);
                            applyPendingKillSwitchIfReady();
                        });
                    });
                }
            });
            return;
        }

        runAction("setKillSwitch", ["config", "set", "kill-switch", value], t("app.title", "Proton VPN"), t("toast.mode_set", "Kill switch set to {mode}", {
            mode: value
        }));
    }

    function setProtocol(protocol) {
        let value = "off";
        if (protocol === "http2") {
            value = "malware-only";
        } else if (protocol === "quic") {
            value = "malware-ads-trackers";
        }
        runAction("setNetshield", ["config", "set", "netshield", value], t("app.title", "Proton VPN"), t("toast.protocol_set", "NetShield set to {protocol}", {
            protocol: value
        }));
    }

    function setUpdateChannel(channel) {
        if (channel === "release") {
            runAction("setProfile", ["config", "set", "vpn-accelerator", "off"], t("app.title", "Proton VPN"), t("toast.channel_set", "Profile set to {channel}", {
                channel: "minimal"
            }));
            return;
        }

        if (channel === "beta") {
            runAction("setProfile", ["config", "set", "vpn-accelerator", "on"], t("app.title", "Proton VPN"), t("toast.channel_set", "Profile set to {channel}", {
                channel: "balanced"
            }));
            return;
        }

        runAction("setProfile", ["config", "set", "port-forwarding", "on"], t("app.title", "Proton VPN"), t("toast.channel_set", "Profile set to {channel}", {
            channel: "power"
        }));
    }

    function setDns(upstream) {
        const normalized = (upstream || "").toString().trim();
        if (!normalized) {
            ToastService.showError(t("app.title", "Proton VPN"), t("toast.dns_empty", "DNS upstream cannot be empty"));
            return;
        }
        runAction("setDns", ["config", "set", "custom-dns", "on", "--dns", normalized], t("app.title", "Proton VPN"), t("toast.dns_set", "DNS set to {dns}", {
            dns: normalized
        }));
    }

    function openTunnelLog() {
        const openScript = `
            resolve_home() {
                if [ -n "$HOME" ]; then
                    printf '%s' "$HOME"
                    return
                fi
                getent passwd "$(id -u)" | cut -d: -f6
            }

            HOME_DIR="$(resolve_home)"
            for candidate in \
                "$HOME_DIR/.cache/Proton/VPN/logs" \
                "$HOME_DIR/.cache/protonvpn/logs"; do
                if [ -d "$candidate" ]; then
                    if command -v xdg-open >/dev/null 2>&1; then
                        xdg-open "$candidate" >/dev/null 2>&1 && exit 0
                    fi
                    printf '%s' "$candidate"
                    exit 45
                fi
            done
            exit 44
        `;

        Proc.runCommand(`${pluginId}.openTunnelLog.${Date.now()}`, ["sh", "-lc", openScript], (stdout, exitCode) => {
            if (exitCode === 0) {
                ToastService.showInfo(t("app.title", "Proton VPN"), t("toast.log_opened", "Log directory opened"));
                return;
            }

            const outputPath = cleanOutput(stdout) || tunnelLogPath;
            if (exitCode === 44) {
                lastError = t("toast.log_missing", "Log directory not found: {path}", { path: outputPath });
                ToastService.showError(t("app.title", "Proton VPN"), lastError);
                return;
            }

            lastError = t("toast.log_open_unsupported", "Could not open a file manager automatically. Logs: {path}", {
                path: outputPath
            });
            ToastService.showError(t("app.title", "Proton VPN"), lastError);
        }, 80);
    }

    function runAction(operation, args, toastTitle, toastMessage, options) {
        if (!cliAvailable) {
            ToastService.showError(t("app.title", "Proton VPN"), t("toast.cli_unavailable", "protonvpn is unavailable"));
            return;
        }

        if (commandRunning) {
            ToastService.showInfo(t("app.title", "Proton VPN"), t("toast.operation_running", "Another operation is running"));
            return;
        }

        commandRunning = true;
        runningCommand = operation;
        lastError = "";
        suspendPolling();

        runCli(operation, args, (stdout, exitCode) => {
            commandRunning = false;
            runningCommand = "";
            resumePolling();

            const clean = cleanOutput(stdout);
            recordLastCommand(args, exitCode, clean);
            if (exitCode === 0) {
                if (toastTitle) {
                    const firstLine = clean.split("\n").map(line => line.trim()).filter(Boolean)[0];
                    ToastService.showInfo(toastTitle, firstLine || toastMessage || t("toast.done", "Done"));
                }

                if (options && options.onSuccess) {
                    options.onSuccess(clean);
                }

                Qt.callLater(() => {
                    refreshStatus();
                    refreshConfig();
                    refreshLicense();
                    refreshLocations();
                });
                return;
            }

            lastError = clean || t("toast.operation_failed", "{operation} failed (code {code})", {
                operation: operation,
                code: exitCode
            });
            const hint = buildLocationHelpHint(lastError);
            if (hint) {
                lastError = `${lastError}\n${hint}`;
            }
            ToastService.showError(t("app.title", "Proton VPN"), lastError);
            refreshStatus();
        });
    }

    Timer {
        id: statusTimer
        interval: 10000
        running: false
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: metadataTimer
        interval: 30000
        running: false
        repeat: true
        onTriggered: {
            root.refreshConfig();
            root.refreshLicense();
        }
    }

    Timer {
        id: locationsTimer
        interval: 60000
        running: false
        repeat: true
        onTriggered: root.refreshLocations()
    }

    Timer {
        id: reconnectTimer
        interval: 5000
        running: false
        repeat: false
        onTriggered: {
            if (!root.isConnected && root.autoReconnectOnDrop && root.cliAvailable && !root.commandRunning) {
                root.reconnectLastTarget();
            }
        }
    }

    Timer {
        id: killSwitchApplyTimer
        interval: 1200
        running: false
        repeat: false
        onTriggered: {
            if (!root.pendingKillSwitchValue) {
                return;
            }

            root.runCli("statusBeforeKillSwitchApply", ["status"], (stdout, exitCode) => {
                root.parseStatus(stdout, exitCode);
                root.applyPendingKillSwitchIfReady();
            });
        }
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId) {
                loadSettings();
            }
        }
    }

    Component.onCompleted: {
        loadSettings();
    }
}
