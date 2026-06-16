{
  description = "Ironworks deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    ironworks.url = "github:2140-dev/ironworks";
    node = {
      url = "git+https://example.org/org/node.git?rev=REPLACE_WITH_SOURCE_SHA";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ironworks,
      node,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      project = ironworks.lib.mkProject {
        inherit pkgs;
        adapter = ironworks.lib.projectAdapters."2140-node";
        src = node;
        flakeLock = ./flake.lock;
        config = {
          projectId = "example-node";
          stages = ironworks.lib.mkStageConfig {
            disable = [
              "harden"
              "stamp"
            ];
          };
        };
      };
    in
    {
      packages.${system} = project.packages;
      checks.${system} = project.checks;
      hydraJobs.${system} = project.hydraJobs;

      nixosConfigurations.hydra = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ironworks.nixosModules.hydra-controller
          ./hosts/hydra/configuration.nix
        ];
      };
    };
}
