# nixpwamaker

A declarative Nix/Home Manager module for generating isolated Firefox-based Progressive Web Apps (PWAs) with custom layouts, extension support, and `firefox-gnome-theme` integration.

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
        nixpwamaker.url = "github:yourusername/nixpwamaker";

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

## Configuration Options

### `programs.pwamaker`

| Option              | Type              | Default | Description                                                                     |
| :------------------ | :---------------- | :------ | :------------------------------------------------------------------------------ |
| `enable`            | bool              | `false` | Enables the PWA Maker module.                                                   |
| `firefoxGnomeTheme` | path              | `null`  | Path to `firefox-gnome-theme`. If set, applies the theme to all generated PWAs. |
| `apps`              | attrsOf submodule | `{}`    | Attribute set of PWA configurations.                                            |

### `programs.pwamaker.apps.<name>`

| Option        | Type            | Description                                                           |
| :------------ | :-------------- | :-------------------------------------------------------------------- |
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
