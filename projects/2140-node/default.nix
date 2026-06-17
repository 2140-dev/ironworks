{
  pkgs,
  src,
  treefmtCheck,
  flakeLock,
  config ? { },
  ...
}:

let
  lib = pkgs.lib;

  aggregate = pkgs.callPackage ../../checks/aggregate.nix { };

  mkNode =
    args:
    pkgs.callPackage ../../pkgs/2140-node.nix (
      {
        inherit src;
      }
      // args
    );

  mkLlvmNode =
    args:
    pkgs.callPackage ../../pkgs/2140-node.nix (
      {
        inherit src;
        stdenv = pkgs.llvmPackages.stdenv;
        extraNativeBuildInputs = [ pkgs.llvmPackages.llvm ];
      }
      // args
    );

  mkCrossNode =
    crossPkgs: args:
    crossPkgs.callPackage ../../pkgs/2140-node.nix (
      {
        inherit src;
      }
      // args
    );

  profile = {
    release = {
      pnameSuffix = "release";
      buildBitcoin = true;
      buildDaemon = true;
      buildCli = true;
      buildTests = true;
      runUnitTests = true;
      buildBench = false;
      buildFuzzBinary = false;
      buildForFuzzing = false;
      buildUtilChainstate = false;
      buildKernelLib = false;
      buildKernelTest = false;
      reduceExports = true;
      warningsAsErrors = false;
      withEmbeddedAsmap = true;
      withUsdt = false;
      withExternalLibmultiprocess = false;
      installMan = true;
    };

    correctness = {
      pnameSuffix = "correctness";
      buildBitcoin = true;
      buildDaemon = true;
      buildCli = true;
      buildTests = true;
      runUnitTests = true;
      buildBench = false;
      buildFuzzBinary = false;
      buildForFuzzing = false;
      buildUtilChainstate = false;
      buildKernelLib = false;
      buildKernelTest = false;
      reduceExports = false;
      warningsAsErrors = false;
      withEmbeddedAsmap = true;
      withUsdt = false;
      withExternalLibmultiprocess = false;
      installMan = false;
    };

    stagingFull = {
      pnameSuffix = "staging-full";
      buildBitcoin = true;
      buildDaemon = true;
      buildCli = true;
      buildTests = true;
      runUnitTests = true;
      buildBench = true;
      buildFuzzBinary = false;
      buildForFuzzing = false;
      buildUtilChainstate = true;
      buildKernelLib = true;
      buildKernelTest = true;
      reduceExports = true;
      warningsAsErrors = false;
      withEmbeddedAsmap = true;
      withUsdt = false;
      withExternalLibmultiprocess = false;
      installMan = false;
    };

    fuzz = {
      pnameSuffix = "fuzz";
      buildBitcoin = false;
      buildDaemon = false;
      buildCli = false;
      buildTests = false;
      runUnitTests = false;
      buildBench = false;
      buildFuzzBinary = true;
      buildForFuzzing = true;
      reduceExports = false;
      warningsAsErrors = false;
      withEmbeddedAsmap = false;
      withUsdt = false;
      installMan = false;
      sanitizers = "fuzzer";
    };

    platform = {
      pnameSuffix = "platform";
      buildBitcoin = true;
      buildDaemon = true;
      buildCli = true;
      buildTests = false;
      runUnitTests = false;
      buildBench = false;
      buildFuzzBinary = false;
      buildForFuzzing = false;
      buildUtilChainstate = false;
      buildKernelLib = false;
      buildKernelTest = false;
      reduceExports = true;
      warningsAsErrors = false;
      withEmbeddedAsmap = true;
      withUsdt = false;
      withExternalLibmultiprocess = false;
      installMan = false;
    };
  };

  packages =
    let
      nodeRelease = mkNode profile.release;
      nodeCorrectness = mkNode profile.correctness;
      nodeStagingFull = mkNode profile.stagingFull;
      nodeFuzz = mkLlvmNode profile.fuzz;
      nodeBenchmarkArtifact = pkgs.callPackage ../../pkgs/benchmark-artifact.nix {
        nodePackage = nodeStagingFull;
      };
      platformPackages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        node-platform-i686 = mkCrossNode pkgs.pkgsCross.gnu32 (
          profile.platform
          // {
            pnameSuffix = "platform-i686";
          }
        );
        node-platform-musl = mkCrossNode pkgs.pkgsCross.musl64 (
          profile.platform
          // {
            pnameSuffix = "platform-musl";
          }
        );
        node-platform-aarch64 = mkCrossNode pkgs.pkgsCross.aarch64-multiplatform (
          profile.platform
          // {
            pnameSuffix = "platform-aarch64";
          }
        );
        node-platform-armv7 = mkCrossNode pkgs.pkgsCross.armv7l-hf-multiplatform (
          profile.platform
          // {
            pnameSuffix = "platform-armv7";
          }
        );
      };
    in
    {
      default = nodeRelease;
      node = nodeCorrectness;
      node-release = nodeRelease;
      node-correctness = nodeCorrectness;
      node-staging-full = nodeStagingFull;
      node-fuzz = nodeFuzz;
      node-benchmark-artifact = nodeBenchmarkArtifact;
    }
    // platformPackages;

  checks =
    let
      nodeCorrectness = packages.node-correctness;
      nodeStagingFull = packages.node-staging-full;
      nodeRelease = packages.node-release;
      nodeFuzz = packages.node-fuzz;
      nodeBenchmarkArtifact = packages.node-benchmark-artifact;

      lint = pkgs.callPackage ../../checks/fast-lint.nix { inherit src; };
      regtestSmoke = pkgs.callPackage ../../checks/regtest-smoke.nix {
        nodePackage = nodeCorrectness;
      };
      stagingRegtestSmoke = pkgs.callPackage ../../checks/regtest-smoke.nix {
        nodePackage = nodeStagingFull;
      };
      benchSanity = pkgs.callPackage ../../checks/bench-sanity.nix {
        nodePackage = nodeStagingFull;
      };
      fuzzSmoke = pkgs.callPackage ../../checks/fuzz-smoke.nix {
        nodePackage = nodeFuzz;
      };
      fuzzTargetsReport = pkgs.callPackage ../../checks/fuzz-targets-report.nix {
        nodePackage = nodeFuzz;
      };
      valgrindFuzzSmoke = pkgs.callPackage ../../checks/valgrind-fuzz-smoke.nix {
        nodePackage = nodeFuzz;
      };
      benchmarkReport = pkgs.callPackage ../../checks/benchmark-report.nix {
        nodePackage = nodeStagingFull;
      };
      releaseInstallSmoke = pkgs.callPackage ../../checks/regtest-smoke.nix {
        nodePackage = nodeRelease;
      };
      releaseManifest = pkgs.callPackage ../../checks/release-manifest.nix {
        nodePackage = nodeRelease;
        inherit flakeLock;
        releaseMetadata = {
          projectId = config.projectId or "2140-node";
          deploymentId = config.deploymentId or null;
          version = config.release.version or null;
          requiredHardenReportIds = config.release.requiredHardenReportIds or [ ];
          benchmarkReportId = config.release.benchmarkReportId or null;
        };
      };
      releaseChecklist = pkgs.callPackage ../../checks/release-checklist.nix {
        inherit releaseManifest;
      };
      hardenIbdSmall = pkgs.callPackage ../../checks/harden-ibd-small.nix {
        fixtureMetadata = ../../harden/fixtures/ibd-small.example.json;
      };
      hardenPreviousReleases = pkgs.callPackage ../../checks/harden-previous-releases.nix {
        fixtureMetadata = ../../harden/fixtures/previous-releases.example.json;
      };
      hardenFuzzCorpus = pkgs.callPackage ../../checks/harden-fuzz-corpus.nix {
        corpusMetadata = ../../harden/fixtures/fuzz-corpus.example.json;
      };

      asanUbsan = mkLlvmNode (
        profile.correctness
        // {
          pnameSuffix = "asan-ubsan";
          sanitizers = "address,undefined,float-divide-by-zero,integer";
        }
      );
      tsan = mkLlvmNode (
        profile.correctness
        // {
          pnameSuffix = "tsan";
          sanitizers = "thread";
        }
      );
      msanBuild = mkLlvmNode (
        profile.correctness
        // {
          pnameSuffix = "msan-build";
          runUnitTests = false;
          sanitizers = "memory";
        }
      );
      clangTidyReport = pkgs.callPackage ../../checks/clang-tidy-report.nix {
        inherit src;
      };
      iwyuReport = pkgs.callPackage ../../checks/iwyu-report.nix {
        inherit src;
      };
      platformChecks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        staging-platform-i686 = packages.node-platform-i686;
        staging-platform-musl = packages.node-platform-musl;
        staging-platform-aarch64 = packages.node-platform-aarch64;
        staging-platform-armv7 = packages.node-platform-armv7;
      };
      analysisChecks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        staging-analysis-clang-tidy-report = clangTidyReport;
        staging-analysis-iwyu-report = iwyuReport;
      };
      fuzzChecks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        staging-fuzz-targets-report = fuzzTargetsReport;
        staging-valgrind-fuzz-smoke = valgrindFuzzSmoke;
      };
    in
    rec {
      correctness = aggregate "2140-node-correctness" [
        formatting
        lint
        nodeCorrectness
        regtestSmoke
      ];

      formatting = treefmtCheck;

      staging = aggregate "2140-node-staging" [
        nodeStagingFull
        stagingRegtestSmoke
        benchSanity
        fuzzSmoke
      ];

      release = aggregate "2140-node-release" [
        nodeRelease
        releaseInstallSmoke
        releaseManifest
        releaseChecklist
      ];

      scheduled = aggregate "2140-node-scheduled" [
        hardenIbdSmall
        hardenPreviousReleases
        hardenFuzzCorpus
      ];

      correctness-format = formatting;
      correctness-lint = lint;
      correctness-linux-unit = nodeCorrectness;
      correctness-regtest-smoke = regtestSmoke;

      staging-full = nodeStagingFull;
      staging-regtest-smoke = stagingRegtestSmoke;
      staging-bench-sanity = benchSanity;
      staging-fuzz-smoke = fuzzSmoke;
      staging-asan-ubsan = asanUbsan;
      staging-tsan = tsan;
      staging-msan-build = msanBuild;

      release-package = nodeRelease;
      release-install-smoke = releaseInstallSmoke;
      release-manifest = releaseManifest;
      release-checklist = releaseChecklist;

      scheduled-required = scheduled;
      scheduled-ibd-small = hardenIbdSmall;
      scheduled-previous-releases = hardenPreviousReleases;
      scheduled-fuzz-corpus = hardenFuzzCorpus;
      scheduled-benchmark-artifact = nodeBenchmarkArtifact;
      scheduled-benchmark-report = benchmarkReport;
    }
    // platformChecks
    // analysisChecks
    // fuzzChecks;

  hydraJobs =
    let
      platformJobs = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        i686 = checks.staging-platform-i686;
        musl = checks.staging-platform-musl;
        aarch64 = checks.staging-platform-aarch64;
        armv7 = checks.staging-platform-armv7;
      };
      analysisJobs = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        clang-tidy-report = checks.staging-analysis-clang-tidy-report;
        iwyu-report = checks.staging-analysis-iwyu-report;
      };
      fuzzJobs = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        targets-report = checks.staging-fuzz-targets-report;
        valgrind-smoke = checks.staging-valgrind-fuzz-smoke;
      };
    in
    {
      correctness = {
        required = checks.correctness;
        format = checks.correctness-format;
        lint = checks.correctness-lint;
        unit = checks.correctness-linux-unit;
        regtest-smoke = checks.correctness-regtest-smoke;
      };
      staging = {
        required = checks.staging;
        full = checks.staging-full;
        regtest-smoke = checks.staging-regtest-smoke;
        bench-sanity = checks.staging-bench-sanity;
        fuzz-smoke = checks.staging-fuzz-smoke;
        fuzz = fuzzJobs;
        platforms = platformJobs;
        analysis = analysisJobs;
        heavy = {
          asan-ubsan = checks.staging-asan-ubsan;
          tsan = checks.staging-tsan;
          msan-build = checks.staging-msan-build;
        };
      };
      release = {
        required = checks.release;
        package = checks.release-package;
        install-smoke = checks.release-install-smoke;
        manifest = checks.release-manifest;
        checklist = checks.release-checklist;
      };
      scheduled = {
        required = checks.scheduled-required;
        ibd-small = checks.scheduled-ibd-small;
        previous-releases = checks.scheduled-previous-releases;
        fuzz-corpus = checks.scheduled-fuzz-corpus;
        benchmark-artifact = checks.scheduled-benchmark-artifact;
        benchmark-report = checks.scheduled-benchmark-report;
      };
    };
in
{
  inherit packages checks hydraJobs;
}
