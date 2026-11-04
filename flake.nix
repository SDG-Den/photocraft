{
  description = "PhotoCraft — a native image editor for layered PSD and raster documents, in pure Rust";

  inputs = {
    # PhotoCraft needs edition 2024 and rustc ≥ 1.95, so the flake tracks unstable. Consumers on a
    # release channel can retarget it: `inputs.photocraft.inputs.nixpkgs.follows = "nixpkgs";`
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Build input of the repository: the fonts the build embeds when `CRAFT_FONTS_DIR` is set.
    # Pinned to the revision the release workflow uses; bump deliberately
    # (`nix flake update craft-fonts`).
    craft-fonts = {
      url = "github:storytold/craft-fonts/b076417b5880bd4154bd22f00695b1d28c6bea83";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      craft-fonts,
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # The AppStream metadata carries a release date. The flake source's own commit date is
      # reproducible, unlike "now"; a tarball or dirty tree without one falls back to the epoch.
      buildDate =
        let
          d = self.lastModifiedDate or "";
        in
        if builtins.stringLength d >= 8 then
          "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}"
        else
          "1970-01-01";

      packageArgs = {
        inherit craft-fonts buildDate;
      };

      forAllSystems = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system; }) system);
    in
    {
      packages = forAllSystems (
        pkgs: _:
        let
          photocraft = pkgs.callPackage ./nix/package.nix packageArgs;
        in
        {
          inherit photocraft;
          default = photocraft;
        }
      );

      # `nixpkgs.overlays = [ inputs.photocraft.overlays.default ]` → `pkgs.photocraft` everywhere.
      overlays.default = final: _prev: {
        photocraft = final.callPackage ./nix/package.nix packageArgs;
      };

      apps = forAllSystems (
        _: system: {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.photocraft;
          };
        }
      );

      devShells = forAllSystems (
        pkgs: system:
        let
          photocraft = self.packages.${system}.photocraft;
        in
        {
          default = pkgs.mkShell {
            # The package's own native inputs, so `cargo build` in the shell needs no extra setup.
            inputsFrom = [ photocraft ];
            packages = with pkgs; [
              cargo
              rustc
              clippy
              rustfmt
              rust-analyzer
            ];
            # `cargo run` dlopens the same libraries as the packaged binary.
            LD_LIBRARY_PATH = lib.makeLibraryPath photocraft.passthru.runtimeLibs;
            RUST_BACKTRACE = "1";
            # Embedded fonts in `cargo run` too; build.rs reads this as CRAFT_FONTS_DIR.
            CRAFT_FONTS_DIR = toString craft-fonts;
          };
        }
      );

      checks = forAllSystems (
        pkgs: system: {
          photocraft = self.packages.${system}.photocraft;

          # Both module entry points evaluate with `enable = true` (no full NixOS evaluation).
          modules = pkgs.callPackage ./nix/module-check.nix {
            photocraft = self.packages.${system}.photocraft;
          };

          # `nix fmt` formats the flake; this keeps it formatted.
          formatting = pkgs.runCommand "photocraft-nix-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            nixfmt --check ${./flake.nix} ${./nix}
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: _: pkgs.nixfmt);

      # Both modules take the package from this flake unless `programs.photocraft.package` is set,
      # so `nixosModules.default`/`homeManagerModules.default` work without the overlay.
      nixosModules.default =
        { pkgs, ... }:
        {
          imports = [ (import ./nix/module.nix { kind = "nixos"; }) ];
          _module.args.photocraftPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.photocraft;
        };

      homeManagerModules.default =
        { pkgs, ... }:
        {
          imports = [ (import ./nix/module.nix { kind = "home-manager"; }) ];
          _module.args.photocraftPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.photocraft;
        };
    };
}
