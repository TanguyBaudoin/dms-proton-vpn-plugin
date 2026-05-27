# Proton VPN - DMS Plugin (MVP Fork)

This is an MVP fork adapted from an existing DMS VPN plugin, now wired to the Proton Linux CLI.

## What Works

- Live status from `protonvpn status`
- Connect/disconnect actions
- Fastest connect (`protonvpn connect`)
- Country/city connect from the widget input
- Country list discovery (`protonvpn countries list`)
- Basic Proton config mappings in the Configuration section:
  - Kill switch
  - NetShield
  - Profile shortcuts (mapped to Proton settings)
  - Custom DNS (`protonvpn config set custom-dns on --dns ...`)

## Requirements

- DankMaterialShell `>= 1.4.0`
- Proton CLI available in PATH (default command: `protonvpn`)
- Active Proton login/session from terminal

## Install

Clone or copy this folder into your DMS plugins directory as `protonVPNplugin`, then run:

```bash
dms ipc plugins reload protonVPNplugin
dms ipc plugins enable protonVPNplugin
```

Then add **Proton VPN** from DMS widget settings.

## Notes

- This is an MVP fork focused on reliable core operations.
- If your Proton CLI binary has a different name/path, set it in plugin settings.
- Logs are opened from Proton cache directories when available.
