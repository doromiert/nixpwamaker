# pwamaker for nixos

a firefox-based web app maker because there was none for some reason

basically clanker-made (i wanted to get it out asap, don't smite me kay)

clanker-made usage and docs or whatever ↓↓↓

# NixPWAMaker: Architecture & Usage

## 1. How It Works (The "Sync Engine" Concept)

NixPWAMaker bridges the gap between the **declarative** world of Nix and the **stateful** nature of Firefox profiles. It operates as a strict **Sync Engine** rather than a simple script.

### The Pipeline

1. **Nix Configuration**: You define your apps in `home-manager`.

2. **Manifest Generation**: During build time, Nix serializes this config into a JSON file at `~/.config/firefoxpwa/nix-manifest.json`.

3. **Activation Script**: When you run `home-manager switch`, the Python `pwamaker` binary is executed with this manifest.

### The Sync Logic

The script (`pwamaker.py`) performs a "Diff & Patch" operation on your system state:

1. **Index Phase**: It scans `~/.local/share/applications` for existing desktop entries created by this tool (identified by `X-FirefoxPWA-Site` keys).

2. **Prune Phase (Delete)**: It compares the existing apps against your new Nix manifest. Any app found on disk but missing from the manifest is **immediately deleted** (profile, site config, and desktop entry are removed).

3. **Deploy Phase (Create/Update)**:

   - **New Apps**: It generates a fresh ULID, copies the template profile, injects `user.js` (for layout) and `policies.json` (for extensions), and registers the site.

   - **Existing Apps**: It updates the manifest, icon, and policies _without_ nuking the user data (cookies/passwords).

### Isolation & Sanitation

To ensure stability, the tool creates **Isolated Profiles**. It copies a base template but aggressively removes "memory" files (`extensions.json`, `startupCache`) to prevent the new PWA from inheriting garbage or conflicting extension states from the template.

## 2. README / Setup Guide

### Installation

**1. Add the Input**
Add `nixpwamaker` to your system `flake.nix`.

```
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
nixpwamaker.url = "github:doromiert/nixpwamaker"; # <--- Add this
};
```

**2. Import the Module**
Pass the input to your Home Manager configuration.

```
# In your home-manager configuration file (e.g., home.nix or pwa.nix)
{ inputs, ... }: {
  imports = [ inputs.nixpwamaker.homeManagerModules.default ];

  programs.nixpwamaker.enable = true;
}
```

### Configuration Example

Define your apps using the `apps` attribute.
programs.nixpwamaker.apps = {
"YouTube" = {
url = "https://www.youtube.com";

    # Icons: Use a local path OR a system icon name (e.g., "youtube")
    icon = "youtube";

    # Profile Template: Required base profile (can be a derivation or path)
    templateProfile = ./resources/firefoxpwa/testprofile;

    # Layout: Comma-separated list (arrows, refresh, spacer, spring)
    layout = "arrows,refresh,spacer";

    # Extensions: ID:URL format
    extensions = [
      "uBlock0@raymondhill.net:https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
    ];

    # Policies: Inject enterprise policies directly
    extraPolicies = {
      DisableTelemetry = true;
      DisablePocket = true;
    };

    # Integration: Keywords & Categories for your launcher
    categories = [ "Network" "Video" ];
    keywords = [ "stream" "google" ];

    # Associations: Register as handler for specific protocols
    mimeTypes = [ "x-scheme-handler/youtube" ];

};
};

### Tips

- **Icons**: If you provide a string (e.g., `"twitter"`), it will use your system's icon theme. If you provide a path (`./icon.png`), it will copy that file into the PWA.

- **Extensions**: You must provide the direct download URL for the XPI. The tool uses `force_installed` policy to install them silently.

- **Updates**: Changing `extraPolicies` or `extensions` in Nix will apply them next time you switch, without deleting your login sessions.
