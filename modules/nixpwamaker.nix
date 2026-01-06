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
  layoutMap = {
    "back" = "back-button";
    "forward" = "forward-button";
    "reload" = "stop-reload-button";
    "home" = "home-button";
    "urlbar" = "urlbar-container";
    "spacer" = "spacer";
    "flexible" = "spring";
    "vertical-spacer" = "vertical-spacer";
    "tabs" = "tabbrowser-tabs";
    "alltabs" = "alltabs-button";
    "newtab" = "new-tab-button";
    "close" = "close-page-button";
    "minimize" = "minimize-button";
    "maximize" = "maximize-button";
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
    "site-info" = "site-info";
    "notifications" = "notifications-button";
    "tracking" = "tracking-protection-button";
    "identity" = "identity-button";
    "permissions" = "permissions-button";
  };

  resolveLayout = layoutList: map (item: layoutMap.${item} or item) layoutList;

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

  # --- Autoconfig Script (Global) ---
  globalMozillaCfg = ''
    // mozilla.cfg - PWA Focus & URL Override
    // IMPORTANT: The first line must be a comment.

    // DEBUG: Print to stdout (terminal) so we know this file loaded.
    if (typeof dump !== 'undefined') dump("PWA_DEBUG: mozilla.cfg is loading...\n");

    try {
      // --- HELPER: XPCOM Service Getter ---
      const getService = (contractID, interfaceName) => 
        Cc[contractID].getService(Ci[interfaceName]);

      // --- 1. SETUP SERVICES (Fallbacks for broken ESMs) ---
      let Services = {};
      
      try {
         // Try Loading Services ESM (Standard)
         if (ChromeUtils.importESModule) {
            const { Services: s } = ChromeUtils.importESModule("resource://gre/modules/Services.sys.mjs");
            Services = s;
         } else {
            // Very old fallback
            Services = ChromeUtils.import("resource://gre/modules/Services.jsm").Services;
         }
      } catch(e) {
         if (typeof dump !== 'undefined') dump("PWA_DEBUG: Services ESM load failed (" + e + "), using XPCOM fallback.\n");
         // Fallback to XPCOM interfaces if module loading fails
         Services = {
           dirsvc: getService("@mozilla.org/file/directory_service;1", "nsIProperties"),
           obs: getService("@mozilla.org/observer-service;1", "nsIObserverService"),
           wm: getService("@mozilla.org/appshell/window-mediator;1", "nsIWindowMediator"),
           scriptSecurityManager: getService("@mozilla.org/scriptsecuritymanager;1", "nsIScriptSecurityManager")
         };
      }
      
      // Ensure SecurityManager is available
      const getSSM = () => {
         if (Services.scriptSecurityManager) return Services.scriptSecurityManager;
         try { return getService("@mozilla.org/scriptsecuritymanager;1", "nsIScriptSecurityManager"); } 
         catch(e) { return null; }
      };

      // --- 2. READ PROFILE CONFIG (pwa.json) ---
      let pwaConfig = {};
      try {
        let profileDir = Services.dirsvc.get("ProfD", Ci.nsIFile);
        let configFile = profileDir.clone();
        configFile.append("pwa.json");
        
        if (configFile.exists()) {
          // Standard File Input Stream
          let fstream = Cc["@mozilla.org/network/file-input-stream;1"]
                          .createInstance(Ci.nsIFileInputStream);
          fstream.init(configFile, -1, 0, 0);
          
          // Converter Stream to handle UTF-8 text properly
          let cstream = Cc["@mozilla.org/intl/converter-input-stream;1"]
                          .createInstance(Ci.nsIConverterInputStream);
          cstream.init(fstream, "UTF-8", 0, 0);
          
          let str = {};
          // Read entire stream
          cstream.readString(-1, str);
          cstream.close();
          fstream.close();
          
          // Parse JSON from string
          pwaConfig = JSON.parse(str.value);
          
          if (typeof dump !== 'undefined') dump("PWA_DEBUG: Loaded pwa.json for " + pwaConfig.name + "\n");
        } else {
          if (typeof dump !== 'undefined') dump("PWA_DEBUG: pwa.json not found in " + profileDir.path + "\n");
        }
      } catch (ex) {
        if (typeof dump !== 'undefined') dump("PWA_DEBUG: Error reading pwa.json: " + ex + "\n");
      }

      // --- 3. APPLY NEW TAB URL (Method A: AboutNewTab Service) ---
      if (pwaConfig.url) {
        try {
          // Attempt to set via AboutNewTab service (Preferred)
          const { AboutNewTab } = ChromeUtils.importESModule("resource:///modules/AboutNewTab.sys.mjs");
          AboutNewTab.newTabURL = pwaConfig.url;
          if (typeof dump !== 'undefined') dump("PWA_DEBUG: Set AboutNewTab.newTabURL to " + pwaConfig.url + "\n");
        } catch(e) {
           if (typeof dump !== 'undefined') dump("PWA_DEBUG: Failed to set AboutNewTab.newTabURL: " + e + "\n");
        }
      }

      // --- 4. DEFINE FOCUS & REDIRECT LOGIC ---
      const forceContentFocus = (win) => {
        if (win && win.gBrowser && win.gBrowser.selectedBrowser) {
          win.setTimeout(() => {
            const browser = win.gBrowser.selectedBrowser;
            
            // Method B: Direct Redirect
            // If the user just opened a new tab, it might be about:newtab, about:blank, or about:home
            const currentSpec = browser.currentURI ? browser.currentURI.spec : "";
            if (pwaConfig.url && (currentSpec === "about:newtab" || currentSpec === "about:home" || currentSpec === "about:blank")) {
               if (typeof dump !== 'undefined') dump("PWA_DEBUG: Forcing redirect from " + currentSpec + " to " + pwaConfig.url + "\n");
               
               try {
                   // fixupAndLoadURIString is robust for partial URLs, but loadURI with ssm is safer for full URLs
                   const ssm = getSSM();
                   const triggeringPrincipal = ssm ? ssm.getSystemPrincipal() : null;
                   
                   if (browser.fixupAndLoadURIString) {
                        browser.fixupAndLoadURIString(pwaConfig.url, { triggeringPrincipal });
                   } else {
                        browser.loadURI(pwaConfig.url, { triggeringPrincipal });
                   }
               } catch(e) {
                   if (typeof dump !== 'undefined') dump("PWA_DEBUG: Redirect failed: " + e + "\n");
               }
            }

            // Force Focus
            browser.focus();
          }, 0);
        }
      };
      
      // Helper to find top window robustly
      const getTopWindow = () => {
         try {
            const { BrowserWindowTracker } = ChromeUtils.importESModule("resource:///modules/BrowserWindowTracker.sys.mjs");
            return BrowserWindowTracker.getTopWindow();
         } catch(e) {
            return Services.wm.getMostRecentWindow("navigator:browser");
         }
      };

      // --- 5. OBSERVERS ---
      const NewTabObserver = {
        observe: function(subject, topic, data) {
          if (topic === "browser-open-newtab-start") {
            const win = getTopWindow();
            forceContentFocus(win);
          }
        }
      };

      const WindowOpenObserver = {
        observe: function(subject, topic, data) {
          const win = subject;
          win.addEventListener("load", () => {
            forceContentFocus(win);
          }, { once: true });
        }
      };

      // Register Observers
      if (Services.obs) {
        Services.obs.addObserver(NewTabObserver, "browser-open-newtab-start", false);
        Services.obs.addObserver(WindowOpenObserver, "domwindowopened", false);
      } else {
         dump("PWA_DEBUG: Observer service missing, cannot register focus hooks.\n");
      }

    } catch (e) {
      if (typeof dump !== 'undefined') dump("PWA_DEBUG: FATAL ERROR in mozilla.cfg: " + e + "\n");
    }
  '';

  # Define config files as store paths to avoid shell escaping issues
  autoconfigJs = pkgs.writeText "autoconfig.js" ''
    pref("general.config.filename", "mozilla.cfg");
    pref("general.config.obscure_value", 0);
    pref("general.config.sandbox_enabled", false);
  '';

  mozillaCfg = pkgs.writeText "mozilla.cfg" globalMozillaCfg;

  # --- Wrapped Firefox Package ---
  pwaFirefox =
    let
      unwrapped = pkgs.firefox.unwrapped or pkgs.firefox;

      # 1. Patched Unwrapped: SymlinkJoin everything EXCEPT the binary.
      patchedUnwrapped = pkgs.symlinkJoin {
        name = "firefox-pwa-patched";
        paths = [ unwrapped ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          if [ -f "$out/lib/firefox/firefox" ]; then
            rm "$out/lib/firefox/firefox"
            cp "${unwrapped}/lib/firefox/firefox" "$out/lib/firefox/firefox"
            
            # Inject Configs - Install to BOTH pref and preferences to be safe
            mkdir -p "$out/lib/firefox/defaults/pref"
            mkdir -p "$out/lib/firefox/defaults/preferences"
            
            cp "${autoconfigJs}" "$out/lib/firefox/defaults/pref/autoconfig.js"
            cp "${autoconfigJs}" "$out/lib/firefox/defaults/preferences/autoconfig.js"
            cp "${mozillaCfg}" "$out/lib/firefox/mozilla.cfg"
          else
            echo "ERROR: Could not find firefox binary in lib/firefox/"
            exit 1
          fi
        '';
      };

    in
    pkgs.runCommand "firefox-pwa-edition"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin

        # 2. Wrapper Patcher
        if [ -f "${pkgs.firefox}/bin/firefox" ]; then
          # Robustly remove the old exec line by filtering lines starting with 'exec'
          # We use grep -v to exclude the line, which is safer than sed regexes against weird whitespace
          grep -v '^\s*exec' "${pkgs.firefox}/bin/firefox" > "$out/bin/firefox"
          
          # Append our custom exec line
          echo 'exec -a "$0" "${patchedUnwrapped}/lib/firefox/firefox" "$@"' >> "$out/bin/firefox"
          
          chmod +x "$out/bin/firefox"
        else
          ln -s "${patchedUnwrapped}/lib/firefox/firefox" "$out/bin/firefox"
        fi
      '';

  # --- Global CSS ---
  globalUserChrome = ''
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
    #nav-bar {
      right: 40px !important;
      height: 46px !important;
    }
    #nav-bar:focus-within {
      z-index: 2147483647 !important;
    }
    #urlbar-container {
      position: fixed !important;
      top: -100px !important; 
      left: 92px;
      right: 40px !important;
      width: calc(100vw - 92px - 92px) !important;
      z-index: 9999 !important;
      pointer-events: none !important;
    }
    #urlbar-container:focus-within {
      top: 6px !important;
      position: fixed !important; 
      pointer-events: auto !important;
    }
    .urlbarView { margin-top: 0 !important; }
    #taskbar-tabs-button { display: none !important; }
  '';

  extensionSubmodule = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      url = mkOption { type = types.str; };
    };
  };

  appSubmodule = types.submodule (
    { config, name, ... }:
    {
      options = {
        id = mkOption {
          type = types.str;
          default = name;
        };
        name = mkOption { type = types.str; };
        url = mkOption { type = types.str; };
        icon = mkOption {
          type = types.str;
          default = "web-browser";
        };
        extensions = mkOption {
          type = types.listOf extensionSubmodule;
          default = [ ];
        };
        layoutStart = mkOption {
          type = types.listOf types.str;
          default = [
            "home"
            "urlbar"
            "reload"
          ];
        };
        layoutEnd = mkOption {
          type = types.listOf types.str;
          default = [ "addons" ];
        };
        userChrome = mkOption {
          type = types.lines;
          default = "";
        };
        userContent = mkOption {
          type = types.lines;
          default = "";
        };
        extraPrefs = mkOption {
          type = types.lines;
          default = "";
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
    enable = mkEnableOption "Firefox PWA Maker Declarative Module (Autoconfig Edition)";
    firefoxGnomeTheme = mkOption {
      type = types.nullOr types.path;
      default = null;
    };
    apps = mkOption {
      default = { };
      type = types.attrsOf appSubmodule;
    };
  };

  config = mkIf cfg.enable {
    xdg.desktopEntries = mapAttrs (key: app: {
      name = app.name;
      genericName = "Web Application";
      exec = "${pwaFirefox}/bin/firefox --no-remote --profile \"${profileBaseDir}/${app.id}\" --name \"FFPWA-${app.id}\" \"${app.url}\"";
      icon = app.icon;
      categories = app.categories;
      settings = {
        Keywords = concatStringsSep ";" app.keywords;
        StartupWMClass = "FFPWA-${app.id}";
      };
    }) cfg.apps;

    home.activation.pwaMakerApply = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        curl = getExe pkgs.curl;
        cleanupScript = ''
          echo "Cleaning up stale PWA profiles..."
          CURRENT_IDS=(${toString (mapAttrsToList (n: v: v.id) cfg.apps)})
          if [ -d "${profileBaseDir}" ]; then
            for dir in "${profileBaseDir}"/*; do
              [ -d "$dir" ] || continue
              base_name=$(basename "$dir")
              keep=0
              for id in "''${CURRENT_IDS[@]}"; do
                if [ "$id" == "$base_name" ]; then keep=1; break; fi
              done
              if [ "$keep" -eq 0 ]; then
                echo "Removing deleted PWA profile: $base_name"
                rm -rf "$dir"
              fi
            done
          fi
        '';

        mkAppScript =
          name: app:
          let
            pwaConfigJson = builtins.toJSON {
              url = app.url;
              id = app.id;
              name = app.name;
            };
            layoutJson = lib.replaceStrings [ "'" ] [ "\\'" ] (mkLayoutState app.layoutStart app.layoutEnd);
            hasBack = elem "back" (app.layoutStart ++ app.layoutEnd);
            hasForward = elem "forward" (app.layoutStart ++ app.layoutEnd);
            hideButtonsCss = ''
              ${optionalString (!hasBack) "#back-button { display: none !important; }"}
              ${optionalString (!hasForward) "#forward-button { display: none !important; }"}
            '';
            baseChrome = optionalString (
              cfg.firefoxGnomeTheme != null
            ) ''@import "firefox-gnome-theme/userChrome.css";'';
            baseContent = optionalString (
              cfg.firefoxGnomeTheme != null
            ) ''@import "firefox-gnome-theme/userContent.css";'';
            fullChromeCss =
              baseChrome + "\n" + globalUserChrome + "\n" + hideButtonsCss + "\n" + app.userChrome;
            fullContentCss = baseContent + "\n" + app.userContent;
            allExtensions = app.extensions;
            builtinExtensionPreferences = {
              "newtab@mozilla.org" = {
                permissions = [
                  "internal:privateBrowsingAllowed"
                  "internal:svgContextPropertiesAllowed"
                ];
                origins = [ ];
                data_collection = [ ];
              };
            };
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
            extensionPreferencesJson = builtins.toJSON (
              builtinExtensionPreferences // userExtensionPreferences
            );
            extensionSettingsJson = builtins.toJSON {
              version = 3;
              commands = { };
              url_overrides = { };
              prefs = { };
              default_search = { };
            };

          in
          ''
            echo "Configuring PWA: ${app.name} (${app.id})"
            PWA_DIR="${profileBaseDir}/${app.id}"
            mkdir -p "$PWA_DIR/chrome" "$PWA_DIR/extensions"
            cat > "$PWA_DIR/pwa.json" <<EOF
            ${pwaConfigJson}
            EOF
            cat > "$PWA_DIR/user.js" <<EOF
            // Generated by nixpwamaker
            user_pref("browser.uiCustomization.state", '${layoutJson}');
            user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
            user_pref("browser.link.open_newwindow", 3);
            user_pref("browser.link.open_newwindow.restriction", 0);
            user_pref("browser.tabs.loadInBackground", false);
            user_pref("browser.search.openintab", false);
            user_pref("browser.taskbarTabs.enabled", false);
            user_pref("browser.shell.checkDefaultBrowser", false);
            user_pref("browser.sessionstore.resume_from_crash", false);
            user_pref("browser.startup.homepage_override.mstone", "ignore");
            user_pref("browser.startup.page", 1);
            user_pref("browser.startup.homepage", "${app.url}");
            // Legacy New Tab URL preference (Fallback)
            user_pref("browser.newtab.url", "${app.url}");
            user_pref("devtools.chrome.enabled", true);
            user_pref("browser.dom.window.dump.enabled", true);
            user_pref("extensions.autoDisableScopes", 0);
            user_pref("extensions.install_distro_addons", true);
            ${optionalString (cfg.firefoxGnomeTheme != null) ''
              user_pref("svg.context-properties.content.enabled", true);
              user_pref("gnomeTheme.hideSingleTab", true);
              user_pref("gnomeTheme.tabsAsHeaderbar", true);
            ''}
            ${app.extraPrefs}
            EOF
            ${optionalString (cfg.firefoxGnomeTheme != null) ''
              ln -sfn "${cfg.firefoxGnomeTheme}" "$PWA_DIR/chrome/firefox-gnome-theme"
            ''}
            cat > "$PWA_DIR/chrome/userChrome.css" <<EOF
            ${fullChromeCss}
            EOF
            cat > "$PWA_DIR/chrome/userContent.css" <<EOF
            ${fullContentCss}
            EOF
            cat > "$PWA_DIR/extension-preferences.json" <<EOF
            ${extensionPreferencesJson}
            EOF
            cat > "$PWA_DIR/extension-settings.json" <<EOF
            ${extensionSettingsJson}
            EOF
            ${concatMapStrings (ext: ''
              EXT_FILE="$PWA_DIR/extensions/${ext.id}.xpi"
              if [ -f "$EXT_FILE" ] && [ ! -s "$EXT_FILE" ]; then rm "$EXT_FILE"; fi
              if [ ! -f "$EXT_FILE" ]; then
                echo "Downloading extension ${ext.id}..."
                ${curl} -f -L -s -o "$EXT_FILE" "${ext.url}" || (rm -f "$EXT_FILE" && echo "Failed to download ${ext.id}")
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
