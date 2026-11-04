# `programs.photocraft` for NixOS and home-manager.
#
# The option set is shared; `kind` selects only the behaviour the target module system can express:
# home-manager writes the settings overlay and the palette variable per user, NixOS installs the
# package and the MIME default for the whole system. NixOS cannot write per-user files, so it never
# writes `settings`.
#
# The overlay is `settings.override.json` beside `preferences.json`
# (`apps/photocraft/src/services.rs`), merged over the saved preferences at start-up. PhotoCraft
# never writes it, so the declarative values survive a normal save. `ui.ron` (window state) is
# deliberately not frozen.
{ kind }:
{
  config,
  lib,
  pkgs,
  # The package of this flake; `flake.nix` passes it through `_module.args`, so importing the
  # module directly needs no overlay.
  photocraftPackage ? pkgs.photocraft,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.photocraft;

  jsonFormat = pkgs.formats.json { };

  # The same list as `packaging/linux/ai.storyteller.photocraft.desktop` (`MimeType=`).
  mimeTypes = [
    "application/x-photocraft"
    "image/x-paintnet"
    "image/openraster"
    "application/x-krita"
    "image/vnd.adobe.photoshop"
    "image/x-psd"
    "image/x-psb"
    "image/png"
    "image/jpeg"
    "image/tiff"
    "image/webp"
    "image/gif"
    "image/bmp"
    "image/x-tga"
    "image/x-icon"
    "image/vnd.microsoft.icon"
    "image/x-portable-anymap"
    "image/x-portable-bitmap"
    "image/x-portable-graymap"
    "image/x-portable-pixmap"
    "image/x-exr"
    "image/vnd.radiance"
    "image/avif"
    "image/qoi"
  ];

  desktopFile = "ai.storyteller.photocraft.desktop";

  # The per-user settings directory: `$XDG_CONFIG_HOME/photocraft` on Linux.
  settingsDir = "${config.xdg.configHome}/photocraft";

  associations = lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  options.programs.photocraft = {
    enable = mkEnableOption "PhotoCraft";

    package = mkOption {
      type = types.package;
      default = photocraftPackage;
      defaultText = lib.literalMD "the `photocraft` package of this flake";
      description = "The PhotoCraft package to install.";
    };

    setAsDefault = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open PhotoCraft documents and the image types in
        `packaging/linux/ai.storyteller.photocraft.desktop` with PhotoCraft by default.
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Free-form preferences merged over the app's settings. Home-manager writes them to
        `settings.override.json`; NixOS ignores them, because it cannot write per-user files.
      '';
    };

    paletteFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional shared palette file, exported as `CRAFT_PALETTE_FILE`.
      '';
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable (
      if kind == "nixos" then
        {
          environment.systemPackages = [ cfg.package ];
          environment.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          xdg.mime.defaultApplications = mkIf cfg.setAsDefault associations;
        }
      else
        {
          home.packages = [ cfg.package ];
          home.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          home.file."${settingsDir}/settings.override.json" = mkIf (cfg.settings != { }) {
            source = jsonFormat.generate "photocraft-settings.override.json" cfg.settings;
          };
          xdg.mimeApps = mkIf cfg.setAsDefault {
            enable = true;
            defaultApplications = associations;
            # Associated even when another application stays the default.
            associations.added = associations;
          };
        }
    ))
  ];
}
