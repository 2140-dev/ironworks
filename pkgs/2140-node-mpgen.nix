{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  capnproto,
  src,
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
in
stdenv.mkDerivation {
  pname = "2140-node-mpgen";
  version = "31.99.0-unstable";

  src = cleanSource;
  sourceRoot = "source/src/ipc/libmultiprocess";

  strictDeps = true;
  cmakeBuildDir = "build";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    capnproto
  ];

  buildInputs = [
    capnproto
  ];

  dontUseCmakeBuildDir = true;

  configurePhase = ''
    runHook preConfigure
    cmake -S . -B "$cmakeBuildDir" -G Ninja \
      -DCMAKE_INSTALL_PREFIX="$out" \
      -DCMAKE_BUILD_TYPE=Release
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build "$cmakeBuildDir" --target mpgen --parallel "$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --build "$cmakeBuildDir" --target install-bin
    runHook postInstall
  '';

  meta = {
    description = "Native libmultiprocess mpgen code generator for 2140-node";
    homepage = "https://github.com/2140-dev/bitcoin";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
