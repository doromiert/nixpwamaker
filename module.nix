{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.nixpwamaker;

  # We use flakeIgnore to prevent trivial formatting issues from breaking the build
  pwamakerBin = pkgs.writers.writePython3Bin "pwamaker" {
    libraries = [ ];
    flakeIgnore = [
      "E501"
      "E302"
      "E701"
      "W293"
      "E305"
      "W292"
      "F821"
    ];
  } (builtins.readFile ./pwamaker.py);

  webAppType = types.submodule {
    options = {
      url = mkOption { type = types.str; };
      icon = mkOption {
        type = types.str;
        description = "Path to file or System Icon Name";
      };
      templateProfile = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      layout = mkOption {
        type = types.str;
        default = "arrows,refresh";
      };
      extensions = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      extraPolicies = mkOption {
        type = types.attrs;
        default = { };
      };

      # Associations
      mimeTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "XDG MimeTypes to associate (e.g., 'x-scheme-handler/figma')";
      };
      categories = mkOption {
        type = types.listOf types.str;
        default = [
          "Network"
          "WebBrowser"
        ];
        description = "XDG Categories (semicolon separated)";
      };
      keywords = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Search keywords";
      };
    };
  };

in
{
  options.programs.nixpwamaker = {
    enable = mkEnableOption "Nix PWA Maker";

    apps = mkOption {
      type = types.attrsOf webAppType;
      default = { };
      description = "Map of PWA names to their configuration.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.firefoxpwa
      pwamakerBin
    ];

    home.file.".config/firefoxpwa/nix-manifest.json".source = pkgs.writeText "pwa-manifest.json" (
      builtins.toJSON cfg.apps
    );

    home.activation.syncPWAs = hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pwamakerBin}/bin/pwamaker \
        --manifest "${config.home.homeDirectory}/.config/firefoxpwa/nix-manifest.json"
    '';
  };
}
