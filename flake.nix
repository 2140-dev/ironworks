{
  description = "Ironworks: Nix packaging, CI stages, and release jobs for Bitcoin node projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    node = {
      url = "git+https://github.com/2140-dev/bitcoin.git?ref=master";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      node,
    }:
    let
      ironworksLib = import ./lib { lib = nixpkgs.lib; };

      projectAdapters = {
        "2140-node" = import ./projects/2140-node;
      };

      publicLib = ironworksLib // {
        inherit projectAdapters;
      };

      nixosModules = {
        hydra-controller = import ./modules/hydra-controller.nix;
        hydra-builder = import ./modules/hydra-builder.nix;
        benchmark-worker = import ./modules/benchmark-worker.nix;
        github-runner = import ./modules/github-runner.nix;
      };

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});

      treefmtEval = forAllSystems (
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );

      mkDefaultProject =
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        ironworksLib.mkProject {
          inherit pkgs;
          adapter = projectAdapters."2140-node";
          src = node;
          treefmtCheck = treefmtEval.${system}.config.build.check self;
          flakeLock = ./flake.lock;
          config = {
            projectId = "2140-node";
            stages = ironworksLib.mkStageConfig {
              enable = [ "harden" ];
            };
          };
        };

      mkApiChecks =
        pkgs:
        let
          fixtureProject = ironworksLib.mkProject {
            inherit pkgs;
            adapter = projectAdapters."2140-node";
            src = ./fixtures/minimal-source;
            config = {
              projectId = "fixture-node";
            };
          };

          disabledTemperProject = ironworksLib.mkProject {
            inherit pkgs;
            adapter = projectAdapters."2140-node";
            src = ./fixtures/minimal-source;
            config = {
              projectId = "fixture-node-disabled-temper";
              stages = ironworksLib.mkStageConfig {
                disable = [ "temper" ];
              };
            };
          };

          enabledHardenProject = ironworksLib.mkProject {
            inherit pkgs;
            adapter = projectAdapters."2140-node";
            src = ./fixtures/minimal-source;
            config = {
              projectId = "fixture-node-enabled-harden";
              stages = ironworksLib.mkStageConfig {
                enable = [ "harden" ];
              };
            };
          };

          moduleEval = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              nixosModules.hydra-controller
              nixosModules.hydra-builder
              nixosModules.benchmark-worker
              nixosModules.github-runner
              (
                { ... }:
                {
                  services.ironworks.hydraController.enable = true;
                  services.ironworks.hydraBuilder.enable = true;
                  services.ironworks.benchmarkWorker.enable = true;
                  services.ironworks.githubRunner = {
                    enable = true;
                    url = "https://github.com/example/project";
                    tokenFile = "/run/secrets/github-runner-token";
                  };
                  boot.loader.grub.devices = [ "nodev" ];
                  fileSystems."/" = {
                    device = "none";
                    fsType = "tmpfs";
                  };
                  system.stateVersion = "25.11";
                }
              )
            ];
          };
        in
        {
          library-api =
            pkgs.runCommand "ironworks-library-api"
              {
                projectPackages = builtins.toJSON (builtins.attrNames fixtureProject.packages);
                projectChecks = builtins.toJSON (builtins.attrNames fixtureProject.checks);
                projectJobsets = builtins.toJSON (builtins.attrNames fixtureProject.hydraJobs);
                disabledDefaultChecks = builtins.toJSON (builtins.attrNames fixtureProject.checks);
                enabledHardenChecks = builtins.toJSON (builtins.attrNames enabledHardenProject.checks);
                enabledHardenJobsets = builtins.toJSON (builtins.attrNames enabledHardenProject.hydraJobs);
                disabledTemperChecks = builtins.toJSON (builtins.attrNames disabledTemperProject.checks);
                disabledTemperJobsets = builtins.toJSON (builtins.attrNames disabledTemperProject.hydraJobs);
                canonicalStages = builtins.toJSON (builtins.attrNames publicLib.stages);
                canonicalStageNames = builtins.toJSON publicLib.stageNames;
                projectStageChecks = builtins.toJSON (builtins.attrNames fixtureProject.stageChecks);
                projectStageJobsets = builtins.toJSON (builtins.attrNames fixtureProject.stageHydraJobs);
                defaultHardenStage = builtins.toJSON {
                  active = fixtureProject.stageChecks.harden.active;
                  enabled = fixtureProject.stageChecks.harden.enabled;
                  implemented = fixtureProject.stageChecks.harden.implemented;
                };
                enabledHardenStage = builtins.toJSON {
                  active = enabledHardenProject.stageChecks.harden.active;
                  enabled = enabledHardenProject.stageChecks.harden.enabled;
                  implemented = enabledHardenProject.stageChecks.harden.implemented;
                };
                moduleNames = builtins.toJSON (builtins.attrNames nixosModules);
                templateNames = builtins.toJSON (builtins.attrNames self.templates);
                moduleSmoke = builtins.toJSON {
                  hydraEnabled = moduleEval.config.services.hydra.enable;
                  hydraPort = moduleEval.config.services.hydra.port;
                  nginxEnabled = moduleEval.config.services.nginx.enable;
                  builderBuildDir = moduleEval.config.nix.settings.build-dir;
                  benchmarkUser = moduleEval.config.users.users.ironworks-bench.name;
                  githubRunnerEnabled = moduleEval.config.services.github-runners.ironworks-runner.enable;
                };
              }
              ''
                test "$projectPackages" != "[]"
                test "$projectChecks" != "[]"
                test "$projectJobsets" != "[]"
                case "$disabledDefaultChecks" in
                  *scheduled*) exit 1 ;;
                esac
                case "$enabledHardenChecks" in
                  *scheduled*) ;;
                  *) exit 1 ;;
                esac
                test "$enabledHardenJobsets" = '["correctness","release","scheduled","staging"]'
                case "$disabledTemperChecks" in
                  *release*) exit 1 ;;
                esac
                test "$disabledTemperJobsets" = '["correctness","staging"]'
                test "$canonicalStages" = '["forge","harden","spark","stamp","temper"]'
                test "$canonicalStageNames" = "$canonicalStages"
                test "$projectStageChecks" = "$canonicalStages"
                test "$projectStageJobsets" = "$canonicalStages"
                test "$defaultHardenStage" = '{"active":false,"enabled":false,"implemented":true}'
                test "$enabledHardenStage" = '{"active":true,"enabled":true,"implemented":true}'
                test "$moduleNames" != "[]"
                test "$templateNames" != "[]"
                test "$moduleSmoke" != "{}"

                {
                  echo "packages=$projectPackages"
                  echo "checks=$projectChecks"
                  echo "jobsets=$projectJobsets"
                  echo "disabledDefaultChecks=$disabledDefaultChecks"
                  echo "enabledHardenChecks=$enabledHardenChecks"
                  echo "enabledHardenJobsets=$enabledHardenJobsets"
                  echo "disabledTemperChecks=$disabledTemperChecks"
                  echo "disabledTemperJobsets=$disabledTemperJobsets"
                  echo "canonicalStages=$canonicalStages"
                  echo "canonicalStageNames=$canonicalStageNames"
                  echo "stageChecks=$projectStageChecks"
                  echo "stageJobsets=$projectStageJobsets"
                  echo "defaultHardenStage=$defaultHardenStage"
                  echo "enabledHardenStage=$enabledHardenStage"
                  echo "modules=$moduleNames"
                  echo "templates=$templateNames"
                  echo "moduleSmoke=$moduleSmoke"
                } > "$out"
              '';

          adapter-2140-node =
            pkgs.runCommand "ironworks-adapter-2140-node-api"
              {
                packageNames = builtins.toJSON (builtins.attrNames (mkDefaultProject pkgs).packages);
                checkNames = builtins.toJSON (builtins.attrNames (mkDefaultProject pkgs).checks);
                jobsetNames = builtins.toJSON (builtins.attrNames (mkDefaultProject pkgs).hydraJobs);
              }
              ''
                test "$packageNames" != "[]"
                test "$checkNames" != "[]"
                test "$jobsetNames" != "[]"
                {
                  echo "packages=$packageNames"
                  echo "checks=$checkNames"
                  echo "jobsets=$jobsetNames"
                } > "$out"
              '';

          tooling =
            pkgs.runCommand "ironworks-tooling-smoke"
              {
                nativeBuildInputs = [ pkgs.python3 ];
              }
              ''
                python3 -m py_compile ${./apps/promote-to-staging.py}
                ${pkgs.bash}/bin/bash -n ${./apps/run-correctness.sh}
                touch "$out"
              '';
        };
    in
    {
      lib = publicLib;

      inherit nixosModules;

      overlays.default = final: prev: {
        ironworks = {
          lib = publicLib;
        };
      };

      templates = {
        deployment = {
          path = ./templates/deployment;
          description = "Deployment flake consuming Ironworks as a library";
        };
        source-workflow = {
          path = ./templates/source-workflow;
          description = "GitHub Actions Spark workflow for a source repository";
        };
      };

      packages = forAllSystems (pkgs: (mkDefaultProject pkgs).packages);

      checks = forAllSystems (pkgs: (mkDefaultProject pkgs).checks // mkApiChecks pkgs);

      hydraJobs = forAllSystems (pkgs: (mkDefaultProject pkgs).hydraJobs);

      apps = forAllSystems (
        pkgs:
        let
          runCorrectness = pkgs.writeShellApplication {
            name = "run-correctness";
            runtimeInputs = [ pkgs.nix ];
            text = builtins.readFile ./apps/run-correctness.sh;
          };

          promoteToStaging = pkgs.writeShellApplication {
            name = "promote-to-staging";
            runtimeInputs = [
              pkgs.gh
              pkgs.git
              pkgs.python3
            ];
            text = ''
              exec ${pkgs.python3}/bin/python3 ${./apps/promote-to-staging.py} "$@"
            '';
          };
        in
        {
          run-correctness = {
            type = "app";
            program = "${runCorrectness}/bin/run-correctness";
            meta.description = "Run the Ironworks Spark correctness stage against a source checkout";
          };
          promote-to-staging = {
            type = "app";
            program = "${promoteToStaging}/bin/promote-to-staging";
            meta.description = "Promote a reviewed source PR to the staging branch";
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.gh
            pkgs.git
            pkgs.nixfmt-tree
            pkgs.ripgrep
          ];
        };
      });

      formatter = forAllSystems (
        pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper
      );
    };
}
