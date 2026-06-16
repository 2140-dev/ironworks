{ lib }:

let
  stages = {
    spark = {
      checkAttr = "correctness";
      checkPrefixes = [ "correctness-" ];
      hydraJobsetAttr = "correctness";
      defaultEnabled = true;
      description = "Fast, local-reproducible PR correctness gate.";
    };

    forge = {
      checkAttr = "staging";
      checkPrefixes = [ "staging-" ];
      hydraJobsetAttr = "staging";
      defaultEnabled = true;
      description = "Hydra-backed staging integration jobs.";
    };

    harden = {
      checkAttr = "scheduled";
      checkPrefixes = [ "scheduled-" ];
      hydraJobsetAttr = "scheduled";
      defaultEnabled = false;
      description = "Scheduled heavy validation such as IBD, fuzzing, and compatibility.";
    };

    temper = {
      checkAttr = "release";
      checkPrefixes = [ "release-" ];
      hydraJobsetAttr = "release";
      defaultEnabled = true;
      description = "Release candidate validation.";
    };

    stamp = {
      checkAttr = "stamp";
      checkPrefixes = [ "stamp-" ];
      hydraJobsetAttr = "stamp";
      defaultEnabled = false;
      description = "Final release publication and provenance checks.";
    };
  };

  defaultStageConfig = lib.mapAttrs (_: stage: { enable = stage.defaultEnabled; }) stages;
  stageNames = builtins.attrNames stages;

  assertKnownStages =
    names:
    let
      unknown = lib.subtractLists stageNames names;
    in
    if unknown == [ ] then
      names
    else
      throw "Unknown Ironworks stage(s): ${lib.concatStringsSep ", " unknown}";

  mkStageEnablement =
    enable: names:
    builtins.listToAttrs (
      map (stageName: {
        name = stageName;
        value.enable = enable;
      }) (assertKnownStages names)
    );

  mkNoopCheck =
    pkgs: name:
    pkgs.runCommand name { } ''
      touch "$out"
    '';

  mkFallbackFlakeLock =
    projectId:
    builtins.toFile "${projectId}-flake.lock" (
      builtins.toJSON {
        nodes = { };
        root = "";
        version = 7;
      }
    );

  normalizeConfig =
    config:
    lib.recursiveUpdate {
      projectId = "ironworks-project";
      stages = defaultStageConfig;
    } config;

  stageEnabled =
    config: stageName: (config.stages.${stageName}.enable or stages.${stageName}.defaultEnabled);

  disabledStageAttrs =
    config: attrName:
    lib.mapAttrsToList (_: stage: stage.${attrName}) (
      lib.filterAttrs (stageName: _: !(stageEnabled config stageName)) stages
    );

  disabledCheckAttrs =
    config: project:
    let
      checkNames = builtins.attrNames (project.checks or { });
      disabledStages = builtins.attrValues (
        lib.filterAttrs (stageName: _: !(stageEnabled config stageName)) stages
      );
      directAttrs = map (stage: stage.checkAttr) disabledStages;
      prefixedAttrs = lib.concatMap (
        stage:
        lib.filter (
          name: lib.any (prefix: lib.hasPrefix prefix name) (stage.checkPrefixes or [ ])
        ) checkNames
      ) disabledStages;
    in
    lib.unique (directAttrs ++ prefixedAttrs);

  applyStageConfig =
    config: project:
    project
    // {
      checks = removeAttrs (project.checks or { }) (disabledCheckAttrs config project);
      hydraJobs = removeAttrs (project.hydraJobs or { }) (disabledStageAttrs config "hydraJobsetAttr");
    };

  mkStageChecksFor =
    config: rawProject: project:
    let
      rawChecks = rawProject.checks or { };
      checks = project.checks or { };
    in
    lib.mapAttrs (
      stageName: stage:
      let
        enabled = stageEnabled config stageName;
        implemented = builtins.hasAttr stage.checkAttr rawChecks;
        active = enabled && builtins.hasAttr stage.checkAttr checks;
      in
      {
        inherit
          active
          enabled
          implemented
          stageName
          ;
        attr = stage.checkAttr;
      }
      // lib.optionalAttrs active {
        check = checks.${stage.checkAttr};
      }
    ) stages;

  mkStageHydraJobsFor =
    config: rawProject: project:
    let
      rawHydraJobs = rawProject.hydraJobs or { };
      hydraJobs = project.hydraJobs or { };
    in
    lib.mapAttrs (
      stageName: stage:
      let
        enabled = stageEnabled config stageName;
        implemented = builtins.hasAttr stage.hydraJobsetAttr rawHydraJobs;
        active = enabled && builtins.hasAttr stage.hydraJobsetAttr hydraJobs;
      in
      {
        inherit
          active
          enabled
          implemented
          stageName
          ;
        attr = stage.hydraJobsetAttr;
      }
      // lib.optionalAttrs active {
        hydraJobs = hydraJobs.${stage.hydraJobsetAttr};
      }
    ) stages;
in
{
  inherit
    stages
    stageNames
    defaultStageConfig
    ;

  mkStageConfig =
    {
      enable ? [ ],
      disable ? [ ],
    }:
    let
      overlap = builtins.filter (stageName: builtins.elem stageName disable) enable;
    in
    if overlap == [ ] then
      (mkStageEnablement true enable) // (mkStageEnablement false disable)
    else
      throw "Ironworks stage(s) cannot be both enabled and disabled: ${lib.concatStringsSep ", " overlap}";

  mkStageChecks =
    project: project.stageChecks or (throw "Ironworks project does not expose stageChecks");

  mkStageHydraJobs =
    project: project.stageHydraJobs or (throw "Ironworks project does not expose stageHydraJobs");

  mkProject =
    {
      pkgs,
      adapter,
      src,
      config ? { },
      treefmtCheck ? null,
      flakeLock ? null,
      ...
    }:
    let
      normalizedConfig = normalizeConfig config;
      projectId = normalizedConfig.projectId;
      rawProject = adapter {
        inherit pkgs src;
        config = normalizedConfig;
        treefmtCheck =
          if treefmtCheck == null then
            mkNoopCheck pkgs "${projectId}-formatting-not-configured"
          else
            treefmtCheck;
        flakeLock = if flakeLock == null then mkFallbackFlakeLock projectId else flakeLock;
      };
      project = applyStageConfig normalizedConfig rawProject;
    in
    project
    // {
      meta = (project.meta or { }) // {
        inherit projectId;
        stages = normalizedConfig.stages;
      };
      stageChecks = mkStageChecksFor normalizedConfig rawProject project;
      stageHydraJobs = mkStageHydraJobsFor normalizedConfig rawProject project;
    };

  mkHydraJobsets =
    project: project.hydraJobs or (throw "Ironworks project does not expose hydraJobs");
}
