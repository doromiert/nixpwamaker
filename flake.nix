{
  description = "NixPWA Maker - Declarative Firefox PWAs for Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    {
      homeManagerModules.default = import ./module.nix;
    };
}
