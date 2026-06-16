{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ironworks.benchmarkWorker;
in
{
  options.services.ironworks.benchmarkWorker = {
    enable = lib.mkEnableOption "an Ironworks benchmark worker";

    user = lib.mkOption {
      type = lib.types.str;
      default = "ironworks-bench";
      description = "User that owns benchmark worker state.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ironworks-bench";
      description = "Benchmark worker state and artifact directory.";
    };

    substituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Binary caches trusted by the benchmark worker.";
    };

    trustedPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Public cache signing keys trusted by the benchmark worker.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = toString cfg.dataDir;
      createHome = true;
    };

    users.groups.${cfg.user} = { };

    environment.systemPackages = [
      pkgs.git
      pkgs.jq
    ];

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = cfg.substituters;
      trusted-public-keys = cfg.trustedPublicKeys;
    };
  };
}
