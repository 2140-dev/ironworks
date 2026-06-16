{
  runCommand,
  nodePackage,
}:

runCommand "2140-node-regtest-smoke"
  {
    requiredSystemFeatures = [ ];
  }
  ''
    set -euo pipefail

    datadir="$TMPDIR/bitcoin"
    mkdir -p "$datadir"

    cleanup() {
      ${nodePackage}/bin/bitcoin-cli -regtest -datadir="$datadir" stop >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    ${nodePackage}/bin/bitcoind \
      -regtest \
      -datadir="$datadir" \
      -daemonwait \
      -listen=0 \
      -dnsseed=0 \
      -fixedseeds=0

    test -S "$datadir/regtest/node.sock"

    ${nodePackage}/bin/bitcoin-cli -regtest -datadir="$datadir" stop
    touch "$out"
  ''
