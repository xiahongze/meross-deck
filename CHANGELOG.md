# Changelog

## 0.2.0 — 2026-11-08

- Panel widgets stay compact with a theme-coloured garage symbol; hover summarises open doors, lights and plugs on, offline devices and stale data; click opens the full controls

## 0.1.0 — 2026-10-17

- Garage door cards with a drawn door, timed travel, and a click-then-confirm control that cancels itself after six seconds.
- Lights and plugs with on/off, plus brightness and colour temperature for lamps that support it.
- Local network first with automatic cloud fallback (MQTT over TLS), or either one alone.
- Terminal sign-in with MFA and region redirect; the session is kept in a 0600 file, never the password.
- The cloud is read at most once per cloud refresh, even when some devices answer locally; polling stops while signed out.
- Every command is logged, with the device's reply, to ~/.cache/meross-deck/commands.log.
- docs/API.md: the Meross cloud HTTP, MQTT and LAN protocols, from the decompiled Android app and live checks.
