{
  jq,
  runCommand,
  corpusMetadata,
}:

runCommand "2140-node-harden-fuzz-corpus"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    mkdir -p "$out"

    jq -e '
      has("corpusId") and
      has("enabled") and
      has("targets") and
      (.targets | type == "array") and
      has("budget") and
      (.budget | has("seconds")) and
      has("archive") and
      (.archive | has("url") and has("sha256"))
    ' ${corpusMetadata} >/dev/null

    cp ${corpusMetadata} "$out/corpus.json"

    jq -n \
      --slurpfile corpus ${corpusMetadata} \
      '{
        stage: "harden",
        job: "fuzz-corpus",
        status: "scaffold",
        reason: "pinned corpus storage and nightly fuzz budget are pending",
        corpus: $corpus[0]
      }' > "$out/report.json"
  ''
