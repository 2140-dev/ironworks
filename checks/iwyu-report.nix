{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  python3,
  jq,
  boost,
  capnproto,
  include-what-you-use,
  libevent,
  openssl,
  sqlite,
  zeromq,
  zlib,
  libsystemtap ? null,
  src,
  maxFiles ? null,
}:

let
  cleanSource = lib.cleanSourceWith {
    src = lib.cleanSource src;
    filter =
      path: type:
      let
        name = baseNameOf path;
      in
      !(type == "directory" && (name == "build" || lib.hasPrefix "cmake-build-" name))
      && name != "CMakeCache.txt";
  };

  maxFilesArg = "--argjson maxFiles ${if maxFiles == null then "0" else toString maxFiles}";
in
stdenv.mkDerivation {
  pname = "2140-node-iwyu-report";
  version = "31.99.0-unstable";

  src = cleanSource;

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    include-what-you-use
    jq
    ninja
    pkg-config
    python3
  ];

  buildInputs = [
    boost
    capnproto
    libevent
    openssl
    sqlite.dev
    zeromq
    zlib
  ]
  ++ lib.optionals (libsystemtap != null) [ libsystemtap ];

  dontFixup = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cmake -S . -B build -G Ninja \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DBUILD_BITCOIN_BIN=ON \
      -DBUILD_DAEMON=ON \
      -DBUILD_CLI=ON \
      -DBUILD_TESTS=ON \
      -DBUILD_BENCH=OFF \
      -DBUILD_FUZZ_BINARY=OFF \
      -DBUILD_FOR_FUZZING=OFF \
      -DBUILD_UTIL_CHAINSTATE=OFF \
      -DBUILD_KERNEL_LIB=OFF \
      -DBUILD_KERNEL_TEST=OFF \
      -DREDUCE_EXPORTS=OFF \
      -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF \
      -DWITH_CCACHE=OFF \
      -DWITH_EMBEDDED_ASMAP=ON \
      -DWITH_USDT=OFF \
      -DWITH_EXTERNAL_LIBMULTIPROCESS=OFF \
      -DINSTALL_MAN=OFF
    cmake --build build --target generate_build_info --parallel "$NIX_BUILD_CORES"

    mkdir -p report
    jq '
      def unsupportedArgs: [
        "-fstack-reuse=none",
        "-fno-extended-identifiers",
        "-Wduplicated-branches",
        "-Wduplicated-cond",
        "-Wlogical-op",
        "-Wbidi-chars=any",
        "-Wleading-whitespace=spaces",
        "-Wtrailing-whitespace=any"
      ];
      map(
        (if has("command") then
          .command |= (reduce unsupportedArgs[] as $arg (. ; gsub(" " + $arg; "")))
        else . end)
        | (if has("arguments") then
          .arguments |= map(select(. as $arg | (unsupportedArgs | index($arg) | not)))
        else . end)
      )
    ' build/compile_commands.json > report/compile_commands.json

    enforced='/src/(((crypto|index|kernel|primitives|script|univalue/(lib|test)|util)/.*|bench/(block_assemble|connectblock)|common/license_info|node/(blockstorage|interfaces|miner|mining_args|utxo_snapshot)|rpc/mining|clientversion|core_io|signet|init)[.]cpp)'
    jq -r ${maxFilesArg} --arg pattern "$enforced" '
      ([.[].file | select(test($pattern))] | unique)
      | if ($maxFiles // 0) > 0 then .[:$maxFiles] else . end
      | .[]
    ' report/compile_commands.json > report/files.txt

    mapfile -t cxx_include_dirs < <(
      echo | ${stdenv.cc}/bin/c++ -E -x c++ - -v 2>&1 \
        | sed -n '/#include <...> search starts here:/,/End of search list./p' \
        | sed '1d;$d;s/^ *//'
    )
    iwyu_extra_args=()
    for include_dir in "''${cxx_include_dirs[@]}"; do
      iwyu_extra_args+=(-isystem"$include_dir")
    done

    status=0
    while IFS= read -r file; do
      echo "### include-what-you-use $file" >> report/iwyu.log
      iwyu_tool.py \
        -p "$PWD/report" \
        "$file" \
        -- \
        -Xiwyu --cxx17ns \
        -Xiwyu --mapping_file="$PWD/contrib/devtools/iwyu/bitcoin.core.imp" \
        -Xiwyu --max_line_length=160 \
        -Xiwyu --check_also="*/primitives/*.h" \
        "''${iwyu_extra_args[@]}" >> report/iwyu.log 2>&1 || status=$?
    done < report/files.txt

    jq -n \
      --arg tool "include-what-you-use" \
      --argjson status "$status" \
      --argjson files "$(wc -l < report/files.txt)" \
      '{tool: $tool, status: $status, files: $files, gating: false}' \
      > report/status.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/ironworks"
    cp -R report "$out/share/ironworks/iwyu"
    runHook postInstall
  '';

  meta = {
    description = "Non-gating include-what-you-use report for 2140-node";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
