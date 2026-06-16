{
  config,
  lib,
  ...
}:

let
  cfg = config.services.ironworks.githubRunner;
in
{
  options.services.ironworks.githubRunner = {
    enable = lib.mkEnableOption "an Ironworks GitHub Actions runner";

    name = lib.mkOption {
      type = lib.types.str;
      default = "ironworks-runner";
      description = "Runner name registered with GitHub.";
    };

    url = lib.mkOption {
      type = lib.types.str;
      example = "https://github.com/2140-dev/bitcoin";
      description = "GitHub repository or organization URL for the runner.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path containing the runner registration token.";
    };

    extraLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ironworks" ];
      description = "GitHub Actions labels for the runner.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.github-runners.${cfg.name} = {
      enable = true;
      inherit (cfg) url tokenFile extraLabels;
      replace = true;
    };

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
