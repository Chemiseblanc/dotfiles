{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "17.0.5";
  assets = {
    aarch64-darwin = {
      name = "omp-darwin-arm64";
      hash = "sha256-wNQ8R7lp77Z/oYT3edGDu1JBHphnK3afsOcdUdWe7Wg=";
    };
    x86_64-darwin = {
      name = "omp-darwin-x64";
      hash = "sha256-Dkta3ZzI95GTtTm1zMp+rn7Jl6cFAVM2u9uWwY2X0X0=";
    };
    aarch64-linux = {
      name = "omp-linux-arm64";
      hash = "sha256-VVBGuVuI0VNP9MqF6lgU74nLNfqKpK87Dj0zEGLanCw=";
    };
    x86_64-linux = {
      name = "omp-linux-x64";
      hash = "sha256-MZ0Iq45fuAxz9zSQfV9Hqou9TqMfehm6z4YRxauibDE=";
    };
  };
  asset = assets.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "oh-my-pi";
  inherit version;

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/omp"

    runHook postInstall
  '';

  meta = {
    description = "AI coding agent for the terminal";
    homepage = "https://omp.sh";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}