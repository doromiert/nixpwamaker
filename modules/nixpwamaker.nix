{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.pwamaker;

  # --- Constants & Paths ---
  profileBaseDir = "${config.home.homeDirectory}/.local/share/pwamaker-profiles";

  # --- Layout Definitions ---
  # Maps user-friendly names to Firefox internal IDs
  layoutMap = {
    # Navigation
    "back" = "back-button";
    "forward" = "forward-button";
    "reload" = "stop-reload-button";
    "home" = "home-button";
    "urlbar" = "urlbar-container";

    # Spacers
    "spacer" = "spacer";
    "flexible" = "spring";
    "vertical-spacer" = "vertical-spacer";

    # Tabs & Windows
    "tabs" = "tabbrowser-tabs";
    "alltabs" = "alltabs-button";
    "newtab" = "new-tab-button";
    "close" = "close-page-button";
    "minimize" = "minimize-button";
    "maximize" = "maximize-button";

    # Tools & Menus
    "menu" = "open-menu-button";
    "addons" = "unified-extensions-button";
    "downloads" = "downloads-button";
    "library" = "library-button";
    "sidebar" = "sidebar-button";
    "history" = "history-panelmenu";
    "bookmarks" = "bookmarks-menu-button";
    "print" = "print-button";
    "find" = "find-button";
    "fullscreen" = "fullscreen-button";
    "zoom" = "zoom-controls";
    "developer" = "developer-button";

    # PWA Specific
    "site-info" = "site-info";
    "notifications" = "notifications-button";
    "tracking" = "tracking-protection-button";
    "identity" = "identity-button";
    "permissions" = "permissions-button";
  };

  # Helper to resolve layout lists to internal IDs
  resolveLayout = layoutList: map (item: layoutMap.${item} or item) layoutList;

  # Helper to generate the browser.uiCustomization.state JSON
  mkLayoutState =
    start: end:
    builtins.toJSON {
      placements = {
        "widget-overflow-fixed-list" = [ ];
        "unified-extensions-area" = [ ];
        "nav-bar" = [ ];
        "toolbar-menubar" = [ "menubar-items" ];
        "TabsToolbar" =
          (resolveLayout start)
          ++ [
            "tabbrowser-tabs"
            "new-tab-button"
          ]
          ++ (resolveLayout end);
        "PersonalToolbar" = [ ];
        "vertical-tabs" = [ ];
      };
      seen =
        (resolveLayout start)
        ++ [
          "tabbrowser-tabs"
          "new-tab-button"
        ]
        ++ (resolveLayout end);
      dirtyAreaCache = [
        "nav-bar"
        "TabsToolbar"
        "PersonalToolbar"
        "toolbar-menubar"
        "vertical-tabs"
        "unified-extensions-area"
      ];
      currentVersion = 20;
      newElementCount = 5;
    };

  # --- Global CSS ---
  # Standard PWA Headerbar & Auto-hide URL bar logic
  globalUserChrome = ''
    /* --- Base Layout Fixes --- */
    .tab-content::before { display: none; }
    .toolbarbutton-icon { --tab-border-radius: 0; }

    .toolbar-items {
      padding-left: 0 !important;
      padding-right: 0px !important;
      margin-right: 46px !important;
      height: 46px !important;
      align-items: center;
    }

    #TabsToolbar, #navigator-toolbox { height: 46px !important; }
    #TabsToolbar-customization-target { height: 46px; }
    .toolbarbutton-1 { height: 34px !important; }

    #PanelUI-menu-button {
      right: 8px;
      top: 6px !important;
      position: absolute;
    }

    [data-l10n-id="browser-window-close-button"] {
      position: relative;
      right: 3px !important;
      top: 17px !important;
    }

    /* Fixed Height is critical for layout stability */
    #nav-bar {
      right: 40px !important;
      height: 46px !important;
    }

    /* Raise index when URL bar is focused so it floats above everything */
    #nav-bar:focus-within {
      z-index: 2147483647 !important;
    }

    /* --- AUTO-HIDING URL BAR LOGIC (Floating "Command Palette" Style) --- */

    #urlbar-container {
      position: fixed !important;
      /* Default State: Hidden above view */
      top: -100px !important; 
      left: 92px;
      right: 40px !important;
      width: calc(100vw - 92px - 92px) !important;
      
      z-index: 9999 !important;
      
      /* Only allow interaction when visible */
      pointer-events: none !important;
    }

    /* STATE 2: FOCUSED (Visible) - Triggers on Ctrl+L */
    #urlbar-container:focus-within {
      /* Bring into view */
      top: 6px !important;
      /* CRITICAL: Keep position FIXED. Switching to absolute causes glitching on blur. */
      position: fixed !important; 
      pointer-events: auto !important;
    }

    /* Optional: Fix for some themes where popup might have negative margins */
    .urlbarView {
      margin-top: 0 !important;
    }
  '';

  # --- Submodules ---

  extensionSubmodule = types.submodule {
    options = {
      id = mkOption {
        type = types.str;
        example = "uBlock0@raymondhill.net";
        description = "Extension ID. Must match the ID in the manifest EXACTLY.";
      };
      url = mkOption {
        type = types.str;
        description = "Direct download URL for the extension (.xpi file).";
      };
    };
  };

  appSubmodule = types.submodule (
    { config, name, ... }:
    {
      options = {
        id = mkOption {
          type = types.str;
          default = name;
          description = "Unique ID for the PWA profile (used for directory name). Defaults to attribute name.";
        };
        name = mkOption {
          type = types.str;
          description = "Display name of the application.";
        };
        url = mkOption {
          type = types.str;
          description = "URL the PWA opens.";
        };
        icon = mkOption {
          type = types.str;
          default = "web-browser";
          description = "Icon name or path.";
        };
        extensions = mkOption {
          type = types.listOf extensionSubmodule;
          default = [ ];
          description = "List of extensions to install.";
        };
        layoutStart = mkOption {
          type = types.listOf types.str;
          default = [
            # "back" - Removed by default
            # "forward" - Removed by default
            "urlbar"
            "reload"
          ];
          description = "Ordered list of items to appear before the tabs.";
        };
        layoutEnd = mkOption {
          type = types.listOf types.str;
          default = [
            "addons"
          ];
          description = "Ordered list of items to appear after the tabs.";
        };
        userChrome = mkOption {
          type = types.lines;
          default = "";
          description = "Custom CSS to append to userChrome.css.";
          example = ''
            #nav-bar { visibility: collapse !important; }
          '';
        };
        userContent = mkOption {
          type = types.lines;
          default = "";
          description = "Custom CSS to append to userContent.css.";
        };
        extraPrefs = mkOption {
          type = types.lines;
          default = "";
          description = "Extra lines to append to user.js (prefs).";
          example = ''
            user_pref("browser.display.use_system_colors", true);
          '';
        };
        categories = mkOption {
          type = types.listOf types.str;
          default = [
            "Network"
            "WebBrowser"
          ];
        };
        keywords = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
    }
  );

in
{
  options.programs.pwamaker = {
    enable = mkEnableOption "Firefox PWA Maker Declarative Module";

    firefoxGnomeTheme = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the firefox-gnome-theme flake input (or local path). If set, enables the theme integration.";
    };

    apps = mkOption {
      description = "Attribute set of PWA configurations.";
      default = { };
      type = types.attrsOf appSubmodule;
    };
  };

  config = mkIf cfg.enable {

    # 1. Desktop Entries
    xdg.desktopEntries = mapAttrs (key: app: {
      name = app.name;
      genericName = "Web Application";
      # --no-remote: Important to allow a separate instance from your main browser
      exec = "${getExe pkgs.firefox} --no-remote --profile \"${profileBaseDir}/${app.id}\" --name \"FFPWA-${app.id}\" \"${app.url}\"";
      icon = app.icon;
      categories = app.categories;
      settings = {
        Keywords = concatStringsSep ";" app.keywords;
        StartupWMClass = "FFPWA-${app.id}";
      };
    }) cfg.apps;

    # 2. Activation Script
    # We generate the script using let-bindings for better readability.
    home.activation.pwaMakerApply = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        curl = getExe pkgs.curl;

        # Script to remove profiles that are no longer in the config
        cleanupScript = ''
          echo "Cleaning up stale PWA profiles..."
          CURRENT_IDS=(${toString (mapAttrsToList (n: v: v.id) cfg.apps)})

          if [ -d "${profileBaseDir}" ]; then
            for dir in "${profileBaseDir}"/*; do
              [ -d "$dir" ] || continue
              base_name=$(basename "$dir")
              
              keep=0
              for id in "''${CURRENT_IDS[@]}"; do
                if [ "$id" == "$base_name" ]; then
                  keep=1
                  break
                fi
              done

              if [ "$keep" -eq 0 ]; then
                echo "Removing deleted PWA profile: $base_name"
                rm -rf "$dir"
              fi
            done
          fi
        '';

        # Function to generate the setup script for a single app
        mkAppScript =
          name: app:
          let
            layoutJson = lib.replaceStrings [ "'" ] [ "\\'" ] (mkLayoutState app.layoutStart app.layoutEnd);

            # Check for back/forward buttons
            hasBack = elem "back" (app.layoutStart ++ app.layoutEnd);
            hasForward = elem "forward" (app.layoutStart ++ app.layoutEnd);
            hideButtonsCss = ''
              ${optionalString (!hasBack) "#back-button { display: none !important; }"}
              ${optionalString (!hasForward) "#forward-button { display: none !important; }"}
            '';

            # Prepare CSS content
            baseChrome = optionalString (
              cfg.firefoxGnomeTheme != null
            ) ''@import "firefox-gnome-theme/userChrome.css";'';
            baseContent = optionalString (
              cfg.firefoxGnomeTheme != null
            ) ''@import "firefox-gnome-theme/userContent.css";'';

            # Combine: Base (Gnome) -> Global Fixes -> Hidden Buttons -> App Specific
            fullChromeCss =
              baseChrome + "\n" + globalUserChrome + "\n" + hideButtonsCss + "\n" + app.userChrome;
            fullContentCss = baseContent + "\n" + app.userContent;

            # --- DEFAULT EXTENSIONS ---
            # New Tab Override (to handle custom new tab URLs and focus)
            defaultExtensions = [
              {
                id = "newtaboverride@agenedia.com";
                url = "https://addons.mozilla.org/firefox/downloads/latest/new-tab-override/latest.xpi";
              }
            ];

            # Merge with user extensions
            allExtensions = defaultExtensions ++ app.extensions;

            # --- EXTENSION CONFIG FILES ---
            # Define default permissions for both built-in and user extensions
            builtinExtensionPreferences = {
              "newtab@mozilla.org" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "addons-search-detection@mozilla.com" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "formautofill@mozilla.org" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "data-leak-blocker@mozilla.com" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "ipp-activator@mozilla.com" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "pictureinpicture@mozilla.org" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "webcompat@mozilla.org" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
              "default-theme@mozilla.org" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
            };

            # Generate preferences for user extensions using their IDs
            userExtensionPreferences = lib.listToAttrs (
              map (ext: {
                name = ext.id;
                value = {
                  permissions = [
                    "internal:privateBrowsingAllowed"
                    "internal:svgContextPropertiesAllowed"
                  ];
                  origins = [ ];
                  data_collection = [ ];
                };
              }) allExtensions
            );

            # Merge lists and convert to JSON
            finalExtensionPreferences = builtinExtensionPreferences // userExtensionPreferences;
            extensionPreferencesJson = builtins.toJSON finalExtensionPreferences;

            # Default settings file to prevent first-run noise
            extensionSettingsJson = builtins.toJSON {
              version = 3;
              commands = { };
              url_overrides = { };
              prefs = { };
              newTabNotification = { };
              homepageNotification = { };
              tabHideNotification = { };
              default_search = { };
            };

          in
          ''
            echo "Configuring PWA: ${app.name} (${app.id})"
            PWA_DIR="${profileBaseDir}/${app.id}"
            mkdir -p "$PWA_DIR/chrome" "$PWA_DIR/extensions"

            # --- Generate user.js ---
            cat > "$PWA_DIR/user.js" <<EOF
            // Generated by nixpwamaker

            // Layout
            user_pref("browser.uiCustomization.state", '${layoutJson}');

            // Standard PWA feel
            user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.sessionstore.resume_from_crash", false);
            user_pref("browser.link.open_newwindow", 3);
            user_pref("browser.startup.homepage_override.mstone", "ignore");

            // Homepage
            user_pref("browser.startup.page", 1);
            user_pref("browser.startup.homepage", "${app.url}");

            // Debugging Support
            user_pref("devtools.chrome.enabled", true);
            user_pref("devtools.debugger.remote-enabled", true);
            user_pref("devtools.debugger.prompt-connection", false);

            // Extensions
            user_pref("extensions.autoDisableScopes", 0);
            user_pref("extensions.install_distro_addons", true);

            ${optionalString (cfg.firefoxGnomeTheme != null) ''
              // Gnome Theme Specific Prefs
              user_pref("svg.context-properties.content.enabled", true);
              user_pref("gnomeTheme.hideSingleTab", true);
              user_pref("gnomeTheme.tabsAsHeaderbar", true);
              user_pref("gnomeTheme.normalWidthTabs", false);
              user_pref("gnomeTheme.activeTabContrast", true);
            ''}

            // Extra Prefs
            ${app.extraPrefs}
            EOF

            # --- Setup Theme Symlinks ---
            ${optionalString (cfg.firefoxGnomeTheme != null) ''
              ln -sfn "${cfg.firefoxGnomeTheme}" "$PWA_DIR/chrome/firefox-gnome-theme"
            ''}

            # --- Write CSS Config ---
            cat > "$PWA_DIR/chrome/userChrome.css" <<EOF
            ${fullChromeCss}
            EOF

            cat > "$PWA_DIR/chrome/userContent.css" <<EOF
            ${fullContentCss}
            EOF

            # --- Write Extension Config Files ---
            # These files ensure extensions have permission to run (e.g. in private windows)
            # and prevent first-run popups.

            cat > "$PWA_DIR/extension-preferences.json" <<EOF
            ${extensionPreferencesJson}
            EOF

            cat > "$PWA_DIR/extension-settings.json" <<EOF
            ${extensionSettingsJson}
            EOF

            # --- Install Extensions (Impure) ---
            # Note: The 'id' in the config MUST match the ID in the extension's manifest.json
            ${concatMapStrings (ext: ''
              EXT_FILE="$PWA_DIR/extensions/${ext.id}.xpi"

              # Cleanup empty failed downloads from previous runs
              if [ -f "$EXT_FILE" ] && [ ! -s "$EXT_FILE" ]; then
                echo "Removing empty file for ${ext.id}"
                rm "$EXT_FILE"
              fi

              if [ ! -f "$EXT_FILE" ]; then
                echo "Downloading extension ${ext.id}..."
                # -f: fail silently on server errors (404)
                # -L: follow redirects
                # || ...: cleanup if download fails
                ${curl} -f -L -s -o "$EXT_FILE" "${ext.url}" || (rm -f "$EXT_FILE" && echo "Failed to download ${ext.id} - Check ID/URL")
              fi
            '') allExtensions}
          '';

      in
      ''
        echo "Starting PWAMaker activation..."
        mkdir -p "${profileBaseDir}"

        ${cleanupScript}

        ${concatStrings (mapAttrsToList mkAppScript cfg.apps)}

        echo "PWAMaker activation complete."
      ''
    );
  };
}
