// @ts-nocheck
.pragma library

function _trimLines(text) {
    return (text || "").split("\n").map(line => line.trim()).filter(Boolean);
}

function parseStatusOutput(clean) {
    const lines = _trimLines(clean);
    if (!lines.length) {
        return { empty: true };
    }

    const full = lines.join("\n");
    const firstLine = lines[0];

    if (/status\s*:\s*disconnected/i.test(full) || /^status:\s*disconnected/i.test(firstLine)) {
        return {
            disconnected: true,
            firstLine: "Status: Disconnected"
        };
    }

    if (/status\s*:\s*connected/i.test(full) || /^status:\s*connected/i.test(firstLine)) {
        let location = "";
        let protocol = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            let match = line.match(/^Server\s*:\s*(.+)$/i);
            if (match) {
                location = match[1].trim();
                continue;
            }

            match = line.match(/^Protocol\s*:\s*(.+)$/i);
            if (match) {
                protocol = match[1].trim();
            }
        }

        return {
            connected: true,
            connectedLocation: location,
            connectedMode: protocol,
            tunnelInterface: "",
            firstLine: firstLine
        };
    }

    return {
        fallback: true,
        isConnected: /connected/i.test(full) && !/disconnected/i.test(full),
        firstLine: firstLine
    };
}

function parseLicenseOutput(clean) {
    const lines = _trimLines(clean);
    let accountEmail = "";

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const accountMatch = line.match(/^Account\s*:\s*'?(.*?)'?$/i);
        if (accountMatch && accountMatch[1]) {
            accountEmail = accountMatch[1].trim();
            continue;
        }

        if (!accountEmail) {
            const emailMatch = line.match(/([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})/i);
            if (emailMatch) {
                accountEmail = emailMatch[1].trim();
            }
        }
    }

    return {
        accountEmail: accountEmail,
        accountTier: "",
        maxDevices: 0,
        subscriptionRenewDate: ""
    };
}

function _parseConfigRows(clean) {
    const lines = (clean || "").split("\n");
    const rows = ({});

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line || /^current\s+configuration/i.test(line) || /^setting\s+/i.test(line)) {
            continue;
        }

        if (/^-{2,}/.test(line.trim())) {
            continue;
        }

        const match = line.match(/^\s*([^\s].*?)\s{2,}(.+?)\s*$/);
        if (!match) {
            continue;
        }

        const key = match[1].trim().toLowerCase();
        const value = match[2].trim();
        if (key) {
            rows[key] = value;
        }
    }

    return rows;
}

function _mapNetshieldToProtocol(value) {
    const text = (value || "").toLowerCase();
    if (text.indexOf("malware-ads-trackers") >= 0 || text.indexOf("track") >= 0) {
        return "quic";
    }
    if (text.indexOf("malware-only") >= 0 || text.indexOf("malware only") >= 0) {
        return "http2";
    }
    return "auto";
}

function _extractDnsCsv(customDnsValue) {
    const text = (customDnsValue || "").toString();
    const bracket = text.match(/\[(.+)\]/);
    if (!bracket || !bracket[1]) {
        return "";
    }
    return bracket[1].replace(/\s+/g, "").replace(/\.\.\./g, "");
}

function parseConfigOutput(clean, currentState) {
    const fallbackState = currentState || {};
    const rows = _parseConfigRows(clean);

    const killSwitch = (rows["kill-switch"] || fallbackState.currentMode || "off").toString().toLowerCase();
    const netshieldRaw = rows["netshield"] || fallbackState.currentProtocolRaw || "off";
    const vpnAccelerator = (rows["vpn-accelerator"] || "off").toString().toLowerCase();
    const portForwarding = (rows["port-forwarding"] || "off").toString().toLowerCase();
    const customDns = rows["custom-dns"] || "off";

    let profile = "release";
    if (portForwarding === "on") {
        profile = "nightly";
    } else if (vpnAccelerator === "on") {
        profile = "beta";
    }

    return {
        currentMode: killSwitch === "standard" ? "STANDARD" : "OFF",
        currentProtocolRaw: netshieldRaw,
        currentProtocol: _mapNetshieldToProtocol(netshieldRaw),
        currentUpdateChannel: profile,
        dnsUpstream: _extractDnsCsv(customDns),
        socksHost: "",
        socksPort: 1080,
        routingMode: "",
        changeSystemDns: false
    };
}

function parseLocationLine(line) {
    const compact = (line || "").trim();
    if (!compact || /^country\s+/i.test(compact) || /^[-=]{2,}/.test(compact)) {
        return null;
    }

    const match = compact.match(/^\s*(.+?)\s{2,}([A-Za-z]{2})\s*$/);
    if (!match) {
        return null;
    }

    const country = match[1].trim();
    const iso = match[2].trim().toUpperCase();
    if (!country || !/^[A-Z]{2}$/.test(iso)) {
        return null;
    }

    return {
        iso: iso,
        country: country,
        city: country,
        ping: -1,
        label: `${country} (${iso})`
    };
}

function parseLocationsOutput(clean) {
    const parsed = [];
    const text = (clean || "").trim();

    // Compact shell export format used as fallback for environments
    // where Proc.runCommand truncates multiline output.
    // Format: "Country Name|CC;Country Name 2|CC;..."
    if (text.indexOf(";") >= 0 && text.indexOf("|") >= 0) {
        const entries = text.split(";");
        for (let i = 0; i < entries.length; i++) {
            const entry = (entries[i] || "").trim();
            if (!entry) {
                continue;
            }

            const match = entry.match(/^(.*?)\|([A-Za-z]{2})$/);
            if (!match) {
                continue;
            }

            const country = (match[1] || "").trim();
            const iso = (match[2] || "").trim().toUpperCase();
            if (!country || !/^[A-Z]{2}$/.test(iso)) {
                continue;
            }

            parsed.push({
                iso: iso,
                country: country,
                city: country,
                ping: -1,
                label: `${country} (${iso})`
            });
        }

        return {
            locations: parsed,
            parseFailed: parsed.length === 0 && !!text
        };
    }

    const lines = text.split("\n");

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].replace(/\s+$/, "");
        const parsedLine = parseLocationLine(line);
        if (parsedLine) {
            parsed.push(parsedLine);
        }
    }

    return {
        locations: parsed,
        parseFailed: parsed.length === 0 && !!text
    };
}

function parseCitiesOutput(clean) {
    const lines = (clean || "").split("\n").map(line => line.trim()).filter(Boolean);
    const cities = [];

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line
                || /^cities\s+in\s+/i.test(line)
                || /^city\s+/i.test(line)
                || /^features\s*$/i.test(line)
                || /^[-=\s]{2,}$/.test(line)
                || /^no\s+cities\b/i.test(line)) {
            continue;
        }

        let cityName = "";
        let featuresText = "";

        const tabular = line.match(/^\s*(.+?)\s{2,}(.+)$/);
        if (tabular) {
            cityName = (tabular[1] || "").trim();
            featuresText = (tabular[2] || "").trim();
        } else {
            cityName = line;
        }

        if (!cityName || /^error:/i.test(cityName) || /^[-=\s]+$/.test(cityName)) {
            continue;
        }

        const features = featuresText ? featuresText.split(",").map(item => item.trim()).filter(Boolean) : [];
        cities.push({
            name: cityName,
            features: features,
            featuresText: featuresText,
            label: featuresText ? `${cityName} (${featuresText})` : cityName
        });
    }

    return {
        cities: cities,
        parseFailed: cities.length === 0 && !!(clean || "").trim()
    };
}
