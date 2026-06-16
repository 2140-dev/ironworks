{
  jq,
  runCommand,
  stdenv,
  nodePackage,
  flakeLock,
  releaseMetadata ? { },
}:

let
  releaseMetadataJson = builtins.toJSON releaseMetadata;
in
runCommand "2140-node-release-manifest"
  {
    nativeBuildInputs = [ jq ];
    inherit flakeLock;
    releaseMetadata = releaseMetadataJson;
  }
  ''
    set -euo pipefail

    mkdir -p "$out"
    cp "$flakeLock" "$out/flake.lock"

    find "${nodePackage}" -type f -perm -0100 -print0 \
      | sort -z \
      | xargs -0 sha256sum > "$out/SHA256SUMS"

    locked_inputs="$(jq -c '
      def locked(name): .nodes[name].locked // .nodes[name].original // null;
      {
        node: locked("node"),
        ironworks: locked("ironworks"),
        nixpkgs: locked("nixpkgs")
      }
    ' "$out/flake.lock")"

    jq -n \
      --arg system "${stdenv.hostPlatform.system}" \
      --arg package "${nodePackage}" \
      --arg flakeLock "$out/flake.lock" \
      --arg checksums "$out/SHA256SUMS" \
      --argjson lockedInputs "$locked_inputs" \
      --argjson releaseMetadata "$releaseMetadata" \
      '{
        schemaVersion: 1,
        name: "2140-node",
        project: {
          id: ($releaseMetadata.projectId // "2140-node"),
          deployment: ($releaseMetadata.deploymentId // null)
        },
        system: $system,
        package: {
          storePath: $package,
          checksums: $checksums
        },
        flakeLock: $flakeLock,
        lockedInputs: $lockedInputs,
        evidence: {
          requiredHardenReportIds: ($releaseMetadata.requiredHardenReportIds // []),
          benchmarkReportId: ($releaseMetadata.benchmarkReportId // null)
        },
        release: {
          version: ($releaseMetadata.version // null)
        }
      }' > "$out/manifest.json"
  ''
