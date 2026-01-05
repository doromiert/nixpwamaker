{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.pwamaker;

  # Define the configuration interface for a single PWA
  pwaOptions = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "The entry point URL for the PWA.";
      };
      name = mkOption {
        type = types.str;
        description = "The display name of the application.";
      };
      icon = mkOption {
        type = types.either types.path types.str;
        description = "Path to icon file OR string name for XDG icon lookup.";
      };
      id = mkOption {
        type = types.str;
        description = "Unique identifier for profile isolation and window grouping.";
      };
      templateProfile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to a base profile directory to copy from.";
      };
      categories = mkOption {
        type = types.listOf types.str;
        default = [
          "Network"
          "WebBrowser"
        ];
        description = "XDG Desktop categories.";
      };
      keywords = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Keywords for the desktop entry.";
      };
      layout = mkOption {
        type = types.str;
        default = "";
        description = "Toolbar layout. If set, the navigation bar will remain visible.";
      };
      extensions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of extension strings in format 'ID:URL'.";
      };
      extraPolicies = mkOption {
        type = types.attrs;
        default = { };
        description = "Firefox policies to apply to this specific PWA.";
      };
    };
  };

  # Helper to parse "ID:URL" string into an attribute set
  parseExtension =
    extStr:
    let
      parts = splitString ":" extStr;
      id = head parts;
      # Re-join the rest in case the URL contains colons (it usually does)
      url = concatStringsSep ":" (tail parts);
    in
    {
      inherit id url;
    };

  # Function to build the launch script for a single PWA
  mkPwaScript =
    app:
    let
      profileDir = "${config.xdg.dataHome}/pwamaker/profiles/${app.id}";

      # Parse extensions list into Policy format
      parsedExtensions = map parseExtension app.extensions;
      extensionSettings = listToAttrs (
        map (ext: {
          name = ext.id;
          value = {
            installation_mode = "force_installed";
            install_url = ext.url;
          };
        }) parsedExtensions
      );

      policies = {
        policies = recursiveUpdate {
          DisableTelemetry = true;
          DisablePocket = true;
          DontCheckDefaultBrowser = true;
          ExtensionSettings = extensionSettings;
        } app.extraPolicies;
      };

      policiesJson = pkgs.writeText "policies.json" (builtins.toJSON policies);

      userJs = pkgs.writeText "user.js" ''
        user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
        user_pref("svg.context-properties.content.enabled", true);
        user_pref("browser.theme.dark-private-windows", false);
        user_pref("widget.gtk.rounded-bottom-corners.enabled", true);
        user_pref("browser.uidensity", 0);
        user_pref("browser.sessionstore.resume_from_crash", false);
        user_pref("browser.cache.disk.enable", true);
      '';

      # Conditional CSS: If layout is set, we assume the user wants the toolbar visible.
      # Otherwise, we hide the nav-bar-customization-target for the "clean" PWA look.
      hideNavBarCss =
        if (app.layout != "") then
          ""
        else
          ''
            /* Hide URL Bar and Navigation items only if no layout is specified */
            #nav-bar-customization-target { visibility: collapse !important; }
          '';

      userChrome = pkgs.writeText "userChrome.css" ''
        @import "firefox-gnome-theme/userChrome.css";

        /* --- PWA MODE PATCH --- */
        #tabbrowser-tabs { visibility: collapse !important; }
        #PersonalToolbar { visibility: collapse !important; }

        ${hideNavBarCss}

        #navigator-toolbox {
          background-color: var(--gnome-headerbar-background, #2e2e32) !important;
          border-bottom: none !important;
          min-height: 38px !important; 
        }

        #nav-bar, #navigator-toolbox, #TabsToolbar {
          -moz-window-dragging: drag !important;
        }

        .titlebar-buttonbox-container {
          display: block !important;
          visibility: visible !important;
          position: absolute !important;
          right: 0;
          top: 0;
          z-index: 1000 !important;
        }
      '';

    in
    pkgs.writeShellScriptBin "launch-${app.id}" ''
      # 1. Create Profile Directory
      mkdir -p "${profileDir}"

      # 2. Handle Template Profile (if provided)
      # We copy strictly, ensuring we can write over it later
      ${optionalString (app.templateProfile != null) ''
        if [ -d "${app.templateProfile}" ]; then
          cp -r --no-preserve=mode "${app.templateProfile}/." "${profileDir}/"
          chmod -R +w "${profileDir}"
        fi
      ''}

      # 3. Create subdirectories (idempotent)
      mkdir -p "${profileDir}/chrome"
      mkdir -p "${profileDir}/distribution"

      # 4. Link GNOME Theme
      ln -sfn ${cfg.firefoxGnomeTheme} "${profileDir}/chrome/firefox-gnome-theme"

      # 5. Install Config Files (Force overwrite)
      ln -sf ${userChrome} "${profileDir}/chrome/userChrome.css"
      ln -sf ${userJs} "${profileDir}/user.js"
      ln -sf ${policiesJson} "${profileDir}/distribution/policies.json"

      # 6. Launch
      exec ${pkgs.firefox}/bin/firefox \
        --profile "${profileDir}" \
        --no-remote \
        --new-window "${app.url}" \
        --name "${app.id}" \
        --class "${app.id}"
    '';

in
{
  options.programs.pwamaker = {
    enable = mkEnableOption "Firefox PWA Maker";

    firefoxGnomeTheme = mkOption {
      type = types.path;
      description = "Path to the firefox-gnome-theme source directory.";
    };

    apps = mkOption {
      type = types.attrsOf pwaOptions;
      default = { };
      description = "Definitions of Progressive Web Apps to generate.";
    };
  };

  config = mkIf cfg.enable {
    xdg.desktopEntries = mapAttrs (key: app: {
      name = app.name;
      exec = "${(mkPwaScript app)}/bin/launch-${app.id}";
      icon = if (builtins.isPath app.icon) then (toString app.icon) else app.icon;
      type = "Application";
      categories = app.categories;
      settings = {
        StartupWMClass = app.id;
        Keywords = concatStringsSep ";" app.keywords;
      };
    }) cfg.apps;
  };
}
