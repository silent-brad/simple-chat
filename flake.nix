{
  description = "Simple Chat — Nim web app built with Jester, Karax, and WebSockets";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildNimPackage {
          pname = "simple_chat";
          version = "0.1.0";
          src = ./.;
          lockFile = ./lock.json;
          buildInputs = [ pkgs.sqlite ];
          nimFlags = [
            "-d:release"
            "-d:useStdLib"
            "--threads:off"
          ];
          meta.mainProgram = "index";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nim2
            nimble
            nim_lk
          ];
        };
      }
    );
}
