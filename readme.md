# nixpwamaker

A declarative Nix/Home Manager module for isolated Firefox and Gnosis web apps. Firefox retains custom layouts, extensions, and `firefox-gnome-theme` integration; Gnosis uses its native application mode and managed desktop entries.

## Overview

`nixpwamaker` allows you to define lightweight, site-specific browser instances in your Home Manager configuration. Unlike standard Firefox profiles, these instances are tailored for an "App-like" experience:

- **Isolated Environments:** Each app has its own profile directory, cookies, and history.
- **App Layout:** Hides standard navigation bars.
- **Command Palette URL Bar:** The URL bar is hidden by default and appears as a floating overlay when focused (Ctrl+L), similar to a command palette.
- **Declarative Extensions:** Install extensions directly via URL and ID.
- **Theme Integration:** Built-in support for `firefox-gnome-theme`.

## Installation

### Flake Input

Add `nixpwamaker` to your `flake.nix`:

```nix
{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        home-manager.url = "github:nix-community/home-manager";

        # Add nixpwamaker
        nixpwamaker.url = "github:doromiert/nixpwamaker";

        # Optional: For GNOME theme integration
        firefox-gnome-theme = {
            url = "github:rafaelmardojai/firefox-gnome-theme";
            flake = false;
        };
    };

    outputs = { self, nixpkgs, home-manager, nixpwamaker, ... }@inputs: {
        nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
            modules = [
                home-manager.nixosModules.home-manager
                {
                    home-manager.users.youruser = {
                        imports = [
                            nixpwamaker.homeManagerModules.pwamaker
                        ];

                        # Pass inputs if using the theme
                        programs.pwamaker.firefoxGnomeTheme = inputs.firefox-gnome-theme;
                    };
                }
            ];
        };
    };
}
```

## Usage

Configure your apps in `home.nix` or your user module.

```nix
programs.pwamaker = {
    enable = true;

    # Optional: Enable GNOME theme integration
    # firefoxGnomeTheme = inputs.firefox-gnome-theme;

    apps = {
        youtube = {
            name = "YouTube";
            url = "https://www.youtube.com";
            icon = "youtube"; # Icon name or path

            # Optional: Install uBlock Origin
            extensions = [
                {
                    id = "uBlock0@raymondhill.net";
                    url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
                };
            ];

            # Optional: Custom CSS
            userChrome = ''
                #page-action-buttons { display: none !important; }
            '';
        };

        chatgpt = {
            name = "ChatGPT";
            url = "https://chat.openai.com";
            icon = "openai";
            categories = [ "Office" "ArtificialIntelligence" ];
        };
    };
};
```

## Gnosis

Select a browser globally or per app. Firefox remains the default.

```nix
programs.pwamaker = {
    enable = true;
    browser = "gnosis";
    # Standalone Home Manager: provide a Gnosis package with declarative web-app support.
    # ZenOS supplies this automatically from ZenPkgs; omit this line there.
    gnosisPackage = inputs.gnosis.packages.${pkgs.stdenv.hostPlatform.system}.default;
    apps.mail = {
        name = "Mail";
        url = "https://mail.example.com/";
        icon = "mail-unread";
        openUrls = [ "mail.example.com" ];
    };
    apps.legacy = {
        browser = "firefox";
        name = "Legacy App";
        url = "https://legacy.example.com/";
    };
};
```

Gnosis launchers use `com.neg-zero.Gnosis.WebApp_<id>.desktop` and the native
`--application-mode` interface. The ID stays stable when the display name or URL
changes. Gnosis creates and maintains its writable profile; activation never
rewrites or removes Gnosis cookies, credentials, or profiles. Removing an app
removes its managed desktop entry only. Existing Firefox data is retained when
switching a declared app to Gnosis.

The dispatcher supports both browsers. With global `browser = "gnosis"`, its
fallback also defaults to Gnosis; an explicit `dispatcher.fallbackBrowser` still
wins. Per-app `openUrls` matching retains substring semantics.

Firefox extensions/search, password-manager switches, toolbar layouts, CSS, and
`extraPrefs` are not Gnosis settings. Explicit per-app overrides are rejected for
Gnosis instead of silently ignored. Global Firefox theme/native-messaging options
apply to Firefox apps only; configure Gnosis browser preferences in Gnosis.

## Configuration Options

### `programs.pwamaker`

| Option              | Type              | Default | Description                                                                     |
| :------------------ | :---------------- | :------ | :------------------------------------------------------------------------------ |
| `browser` | enum | `"firefox"` | Default backend: `"firefox"` or `"gnosis"`. |
| `gnosisPackage` | package or null | `pkgs.gnosis` when available | Package providing Gnosis with declarative web-app support. |
| `enable`            | bool              | `false` | Enables the PWA Maker module.                                                   |
| `firefoxGnomeTheme` | path              | `null`  | Path to `firefox-gnome-theme`. If set, applies the theme to all generated PWAs. |
| `apps`              | attrsOf submodule | `{}`    | Attribute set of PWA configurations.                                            |

### `programs.pwamaker.apps.<name>`

| Option        | Type            | Description                                                           |
| :------------ | :-------------- | :-------------------------------------------------------------------- |
| `browser` | enum | Browser backend; inherits the global selector. |
| `id`          | string          | Unique ID for the profile/directory. Defaults to the attribute name.  |
| `name`        | string          | Display name in the desktop entry.                                    |
| `url`         | string          | The target URL for the PWA.                                           |
| `icon`        | string          | Icon name (from icon theme) or absolute path. Default: `web-browser`. |
| `extensions`  | list            | List of extensions to install (see below).                            |
| `layoutStart` | list of strings | Items to the left of tabs. Default: `["urlbar", "reload"]`.           |
| `layoutEnd`   | list of strings | Items to the right of tabs. Default: `["addons"]`.                    |
| `userChrome`  | lines           | Custom CSS appended to `userChrome.css`.                              |
| `userContent` | lines           | Custom CSS appended to `userContent.css`.                             |
| `extraPrefs`  | lines           | Extra lines appended to `user.js`.                                    |
| `categories`  | list of strings | Desktop entry categories. Default: `["Network", "WebBrowser"]`.       |

### Extensions Submodule

To install extensions, you must provide the exact Extension ID (found in `manifest.json` of the extension) and a direct download URL.

```nix
extensions = [
    {
        id = "uBlock0@raymondhill.net";
        url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
    }
];
```

## Layout Customization

You can customize the toolbar layout using the `layoutStart` and `layoutEnd` options. Available identifiers:

- **Navigation:** `back`, `forward`, `reload`, `home`, `urlbar`
- **Spacers:** `spacer`, `flexible`, `vertical-spacer`
- **Window:** `minimize`, `maximize`, `close`
- **Tools:** `menu`, `addons`, `downloads`, `library`, `sidebar`, `history`, `bookmarks`, `print`, `find`, `fullscreen`, `developer`
- **PWA:** `site-info`, `notifications`, `tracking`, `identity`, `permissions`

**Note:** The URL bar is styled to be hidden by default. Press `Ctrl+L` to float it over the content.

## Maintenance

The activation script automatically cleans up stale profiles in `~/.local/share/pwamaker-profiles` that are no longer defined in your configuration.


## Tests

`tests/default.nix` accepts `pkgs` and the matching `homeManager` flake input.
It evaluates real Home Manager configurations for mixed/default/Gnosis-only
apps, invalid configuration, and stable IDs, then validates and launches the
generated desktop file using GIO against a test browser. It also executes URL
dispatch and fallback routing. ZenPkgs runs it as the `nixpwamaker` flake check;
this test does not require opening or restarting a human browser.
