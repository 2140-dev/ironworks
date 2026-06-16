{
  config,
  lib,
  ...
}:

let
  cfg = config.services.ironworks.hydraBuilder;
in
{
  options.services.ironworks.hydraBuilder = {
    enable = lib.mkEnableOption "an Ironworks remote Hydra builder";

    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Maximum concurrent local Nix builds.";
    };

    cores = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      description = "Cores passed to each build. Zero lets Nix decide.";
    };

    buildDir = lib.mkOption {
      type = lib.types.path;
      default = "/build";
      description = "Directory Nix should use for temporary build trees.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      max-jobs = cfg.maxJobs;
      cores = cfg.cores;
      build-dir = toString cfg.buildDir;
      builders-use-substitutes = true;
    };
  };
}
