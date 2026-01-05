{
  description = "Firefox PWA Maker Module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    {
      # We simply export the module file.
      # The consumer (your system config) will provide the theme input via options.
      homeManagerModules.pwamaker = import ./modules/nixpwamaker.nix;
    };
}
