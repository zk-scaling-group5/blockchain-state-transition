{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    my-utils = {
      url = "github:nmrshll/nix-utils";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };
  };

  outputs = { self, nixpkgs, utils, rust-overlay, my-utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        customRust = pkgs.rust-bin.stable."1.80.0".default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ ];
        };

        baseBuildInputs = with pkgs; [
          customRust
          pkg-config
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          pkgs.darwin.apple_sdk.frameworks.CoreServices
          pkgs.darwin.apple_sdk.frameworks.CoreFoundation
          pkgs.darwin.apple_sdk.frameworks.Foundation
          pkgs.darwin.libunwind
          pkgs.libiconv
        ];

        devInputs = with pkgs; [
          nixpkgs-fmt
          cargo-nextest
          # nargo
          nargo_prebuilt
          bb_prebuilt
          pkgs.llvmPackages_12.libunwind
          jq
          # llvm_16
          # libllvm
          # watchexec
        ];

        # nargo = pkgs.rustPlatform.buildRustPackage
        #   rec
        #   {
        #     pname = "nargo-cli";
        #     version = self.shortRev or self.dirtyShortRev or "unknown";
        #     src = pkgs.fetchFromGitHub
        #       {
        #         owner = "noir-lang";
        #         repo = "noir";
        #         rev = "v0.36.0";
        #         sha256 = "sha256-csltqJG2UxlCqvMdQhZHJVtmGcaLXpF5RyCjKZMfStg=";
        #       };
        #     env = {
        #       GIT_COMMIT = self.shortRev or self.dirtyShortRev or "unknown";
        #       GIT_DIRTY = "false";
        #     };
        #     cargoLock = {
        #       # allowBuiltinFetchGit = true;
        #       lockFile = "${src}/Cargo.lock";
        #       outputHashes = {
        #         "clap-markdown-0.1.3" = "sha256-2vG7x+7T7FrymDvbsR35l4pVzgixxq9paXYNeKenrkQ=";
        #       };
        #     };
        #     nativeBuildInputs = with pkgs; [
        #       clang
        #       pkg-config
        #     ];
        #     buildInputs = baseBuildInputs;
        #     buildNoDefaultFeatures = true;
        #   };

        nargo_prebuilt =
          pkgs.stdenv.mkDerivation {
            name = "nargo";
            src = pkgs.fetchurl
              {
                # url = "https://github.com/noir-lang/noirup/releases/latest/download";
                url = "https://github.com/noir-lang/noir/releases/download/v0.36.0/nargo-x86_64-apple-darwin.tar.gz";
                sha256 = "sha256-uY87a5r5GNAB0sSW+UH+6rGKcaEXQY0oL1n5os/egXQ=";
              };
            sourceRoot = ".";
            installPhase = ''
              install -m755 -D nargo $out/bin/nargo
            '';
          };

        bb_prebuilt =
          let
            BBUP_TAG = "aztec-packages-v0.62.0";
            ARCHITECTURE = "x86_64";
            PLATFORM = "apple-darwin";
          in
          pkgs.stdenv.mkDerivation
            rec {
              name = "bbup";
              src = pkgs.fetchurl
                {
                  # url = "https://raw.githubusercontent.com/noir-lang/noir/v0.36.0/scripts/install_bb.sh";
                  # url = "https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/cpp/installation/bbup";
                  url = "https://github.com/AztecProtocol/aztec-packages/releases/download/${BBUP_TAG}/barretenberg-${ARCHITECTURE}-${PLATFORM}.tar.gz";
                  sha256 = "sha256-AVRxO2CeTaaqJ4YDPYaAKaPhjqeLqJYVAEeHv+4NpXI=";
                };
              sourceRoot = ".";
              installPhase = ''
                mkdir -p $out/bin
                tar -xzC $out/bin -f ${src}
                install -m755 -D bb $out/bin/bb
              '';
              fixupPhase = ''
                install_name_tool -change /usr/local/opt/llvm@16/lib/libunwind.1.dylib ${pkgs.llvmPackages_12.libunwind}/lib/libunwind.1.dylib $out/bin/bb
              '';
            };


        env = {
          RUST_BACKTRACE = "1";
        };

        scripts = with pkgs; [
          # (writeShellScriptBin "deps" ''
          #   curl -L noirup.dev | bash
          #   noirup
          #   curl -L bbup.dev | bash
          #   bbup
          # '')
          (writeShellScriptBin "utest" ''cargo test --manifest-path ./mk_state/Cargo.toml -- --nocapture'')
          (writeShellScriptBin "nr" ''
            nargo test --package hello_world --show-output
            # check; execute; prove; verify
          '')

          (writeShellScriptBin "check" ''nargo check --package hello_world'')
          (writeShellScriptBin "execute" ''nargo execute --package hello_world'')
          (writeShellScriptBin "prove" ''bb prove -b ./target/hello_world.json -w ./target/hello_world.gz -o ./target/proof'')
          (writeShellScriptBin "verify" ''
            bb write_vk -b ./target/hello_world.json -o ./target/vk
            bb verify -k ./target/vk -p ./target/proof
          '')
          (writeShellScriptBin "inputs" ''head -c 32 ./target/proof | od -An -v -t x1 | tr -d ''' \n''' '')

          # (writeShellScriptBin "bb" ''
          #   DYLD_LIBRARY_PATH=${pkgs.llvmPackages_12.libunwind}/lib:$DYLD_LIBRARY_PATH ${bb_prebuilt}/bin/bb
          # '')
          # (writeShellScriptBin "patch" ''otool -L ${bb_prebuilt}/bin/bb'')
          # (writeScriptBin "run" ''cargo run -- "$@" '')
          # (writeScriptBin "utest" ''cargo nextest run --workspace --nocapture -- $SINGLE_TEST '')
        ];

      in
      {
        devShells.default = with pkgs; mkShell {
          inherit env;
          buildInputs = baseBuildInputs ++ devInputs ++ scripts;
          shellHook = "
              ${my-utils.binaries.${system}.configure-vscode-rust};
              ${my-utils.binaries.${system}.configure-vscode-noir}; 
              dotenv
            ";
        };
      }
    );
}




