.pragma library

// Pure helpers for Meross Deck: no QML objects, so tests can call them directly.

// A channel's identity across polls.
function key(uuid, channel) {
    return uuid + ":" + channel;
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// UTF-8 bytes to base64. Qt.btoa's string form is deprecated in Qt 6.
function base64(text) {
    const bytes = [];
    const utf8 = unescape(encodeURIComponent(text));
    for (let i = 0; i < utf8.length; i++)
        bytes.push(utf8.charCodeAt(i));
    let out = "";
    for (let i = 0; i < bytes.length; i += 3) {
        const n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
        out += B64[n >> 18 & 63] + B64[n >> 12 & 63] + (i + 1 < bytes.length ? B64[n >> 6 & 63] : "=") + (i + 2 < bytes.length ? B64[n & 63] : "=");
    }
    return out;
}

function unbase64(text) {
    let bits = 0, value = 0, utf8 = "";
    for (const c of text.replace(/=+$/, "")) {
        value = (value << 6) | B64.indexOf(c);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            utf8 += String.fromCharCode((value >> bits) & 255);
        }
    }
    return decodeURIComponent(escape(utf8));
}

// Helper arguments travel as base64 JSON so names and values never meet a shell.
function encodeRequest(request) {
    return base64(JSON.stringify(request));
}

function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

function helperArgs(command, transport) {
    const args = [command];
    if (transport === "lan")
        args.push("--lan-only");
    else if (transport === "cloud")
        args.push("--cloud-only");
    return args;
}

// Parses one helper run. Returns {ok, data} or {ok: false, kind, reason}.
function parseResult(exitCode, stdout) {
    if (exitCode === 127)
        return { ok: false, kind: "setup", reason: "python3 not found" };
    let data;
    try {
        data = JSON.parse(stdout);
    } catch (e) {
        return { ok: false, kind: "network", reason: exitCode === 0 ? "unreadable helper output" : "helper failed (" + exitCode + ")" };
    }
    if (!data || data.ok !== true)
        return { ok: false, kind: (data && data.kind) || "network", reason: (data && data.error) || "helper failed" };
    return { ok: true, data: data };
}

// The door's phase from its reported state and any motion we started or saw.
// motion = {open, started, until}; the protocol has no moving state, so the
// travel time comes from the door's configured duration.
function doorPhase(channel, motion, now) {
    if (motion && now < motion.until) {
        const span = Math.max(1, motion.until - motion.started);
        const f = Math.min(1, Math.max(0, (now - motion.started) / span));
        return { phase: motion.open ? "opening" : "closing", progress: motion.open ? f : 1 - f, remaining: Math.ceil((motion.until - now) / 1000) };
    }
    return { phase: channel.open ? "open" : "closed", progress: channel.open ? 1 : 0, remaining: 0 };
}

// Applies pending edits {key: {field: value, until}} over a poll.
function withPending(devices, pending, now) {
    return devices.map(function(device) {
        const channels = device.channels.map(function(ch) {
            const edit = pending[key(device.uuid, ch.channel)];
            if (!edit || edit.until < now)
                return ch;
            const copy = Object.assign({}, ch);
            for (const field in edit.values)
                copy[field] = edit.values[field];
            return copy;
        });
        return Object.assign({}, device, { channels: channels });
    });
}

// True when the poll already shows every pending value.
function pendingSettled(channel, edit) {
    for (const field in edit.values) {
        if (channel[field] !== edit.values[field])
            return false;
    }
    return true;
}

function findChannel(devices, uuid, channel) {
    for (const d of devices) {
        if (d.uuid !== uuid)
            continue;
        for (const ch of d.channels) {
            if (ch.channel === channel)
                return ch;
        }
    }
    return null;
}

function doors(devices, hidden) {
    const out = [];
    for (const d of devices) {
        if (d.kind !== "garage" || hidden.indexOf(d.uuid) >= 0)
            continue;
        for (const ch of d.channels)
            out.push({ device: d, channel: ch });
        if (d.channels.length === 0)
            out.push({ device: d, channel: null });
    }
    return out;
}

// Lights, plugs and switches with live channels; offline ones are listed apart.
function switches(devices, hidden, online) {
    const out = [];
    for (const d of devices) {
        if (d.kind === "garage" || hidden.indexOf(d.uuid) >= 0)
            continue;
        const live = d.online && d.channels.length > 0;
        if (live !== online)
            continue;
        if (!online) {
            out.push({ device: d, channel: null });
            continue;
        }
        for (const ch of d.channels)
            out.push({ device: d, channel: ch });
    }
    return out;
}

// Meross colour temperature runs 1 (warm) to 100 (cool); about 2700 K to 6500 K.
function kelvin(temperature) {
    return Math.round(2700 + (Math.max(1, Math.min(100, temperature)) - 1) * (3800 / 99));
}

function warmth(temperature) {
    const stops = [[1, [255, 166, 87]], [50, [255, 228, 196]], [100, [196, 220, 255]]];
    const t = Math.max(1, Math.min(100, temperature || 50));
    for (let i = 1; i < stops.length; i++) {
        if (t <= stops[i][0]) {
            const f = (t - stops[i - 1][0]) / (stops[i][0] - stops[i - 1][0]);
            const a = stops[i - 1][1], b = stops[i][1];
            return Qt.rgba((a[0] + (b[0] - a[0]) * f) / 255, (a[1] + (b[1] - a[1]) * f) / 255, (a[2] + (b[2] - a[2]) * f) / 255, 1);
        }
    }
    return Qt.rgba(196 / 255, 220 / 255, 1, 1);
}
