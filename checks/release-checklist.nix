{
  jq,
  runCommand,
  releaseManifest,
}:

runCommand "2140-node-release-checklist"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    manifest="${releaseManifest}/manifest.json"
    mkdir -p "$out"

    project_id="$(jq -r '.project.id' "$manifest")"
    package_path="$(jq -r '.package.storePath' "$manifest")"
    source_rev="$(jq -r '.lockedInputs.node.rev // .lockedInputs.node.ref // .lockedInputs.node.path // "unknown"' "$manifest")"
    ironworks_rev="$(jq -r '.lockedInputs.ironworks.rev // .lockedInputs.ironworks.ref // .lockedInputs.ironworks.path // "unknown"' "$manifest")"
    nixpkgs_rev="$(jq -r '.lockedInputs.nixpkgs.rev // .lockedInputs.nixpkgs.ref // .lockedInputs.nixpkgs.path // "unknown"' "$manifest")"
    benchmark_report="$(jq -r '.evidence.benchmarkReportId // "pending"' "$manifest")"
    harden_reports="$(jq -r '.evidence.requiredHardenReportIds | length' "$manifest")"

    cp "$manifest" "$out/manifest.json"

    {
      echo "# $project_id Release Checklist"
      echo
      echo "Manifest: $manifest"
      echo "Package: $package_path"
      echo
      echo "## Locked Inputs"
      echo
      echo "- Source: $source_rev"
      echo "- Ironworks: $ironworks_rev"
      echo "- nixpkgs: $nixpkgs_rev"
      echo
      echo "## Temper Review"
      echo
      echo "- [ ] Hydra release jobset is green."
      echo "- [ ] Release package checksums in manifest are reviewed."
      echo "- [ ] Required harden reports are current and green. Count: $harden_reports."
      echo "- [ ] Benchmark report is reviewed. Report: $benchmark_report."
      echo "- [ ] Any accepted benchmark regression is recorded."
      echo "- [ ] No unresolved staging-blocker issue applies to this candidate."
    } > "$out/release-checklist.md"
  ''
