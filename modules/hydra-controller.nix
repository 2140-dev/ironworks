{
  config,
  lib,
  ...
}:

let
  cfg = config.services.ironworks.hydraController;
in
{
  options.services.ironworks.hydraController = {
    enable = lib.mkEnableOption "an Ironworks Hydra controller";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "hydra.example.invalid";
      description = "Public hostname for the Hydra UI.";
    };

    hydraURL = lib.mkOption {
      type = lib.types.str;
      default = "https://${cfg.hostName}";
      defaultText = "https://<hostName>";
      description = "Canonical Hydra URL.";
    };

    notificationSender = lib.mkOption {
      type = lib.types.str;
      default = "hydra@${cfg.hostName}";
      defaultText = "hydra@<hostName>";
      description = "Sender address for Hydra notifications.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Local Hydra web server port.";
    };

    useACME = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether nginx should request an ACME certificate.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "ACME account email. Required when useACME is true.";
    };

    minimumDiskFree = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 300;
      description = "Hydra queue-runner free disk threshold in GiB.";
    };

    minimumDiskFreeEvaluator = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 100;
      description = "Hydra evaluator free disk threshold in GiB.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.useACME || cfg.acmeEmail != null;
        message = "services.ironworks.hydraController.acmeEmail must be set when useACME is true.";
      }
    ];

    services.hydra = {
      enable = true;
      hydraURL = cfg.hydraURL;
      notificationSender = cfg.notificationSender;
      useSubstitutes = true;
      inherit (cfg) port minimumDiskFree minimumDiskFreeEvaluator;
    };

    services.postgresql.enable = true;

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${cfg.hostName} = {
        enableACME = cfg.useACME;
        forceSSL = cfg.useACME;
        locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
      };
    };

    security.acme = lib.mkIf cfg.useACME {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [
      22
      80
      443
    ];

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "hydra-queue-runner"
      ];
      builders-use-substitutes = true;
      allowed-uris = [
        "github:"
        "git+https://github.com/"
        "git+ssh://github.com/"
        "https://github.com/"
      ];
    };
  };
}
