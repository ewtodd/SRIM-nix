{
  description = "SRIM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        wrapWine = ((import ./wrapWine.nix) { inherit pkgs; }).wrapWine;
        installer = builtins.fetchurl {
          url = "http://srim.org/SRIM/SRIM-2013-Std.e";
          sha256 =
            "sha256:0vw8siwpn6m3rxarrw24y89j2405qjk6ns80jfq74zpisd5q343z";
        };
        wine = pkgs.wineWowPackages.stagingFull;
        srim_bin = wrapWine {
          wine = wine;
          name = "SRIM";
          is64bits = false;
          executable = "$WINEPREFIX/drive_c/SRIM/SRIM.exe";
          chdir = "$WINEPREFIX/drive_c/SRIM";
          firstrunScript = ''
            pushd "$WINEPREFIX/drive_c"
              mkdir -p SRIM
              cd SRIM
              
              cp ${installer} ./SRIM-2013-Std.e
              chmod +w ./SRIM-2013-Std.e
              
              ${wine}/bin/wine ./SRIM-2013-Std.e
              
              sleep 3
              
              if [ -d "SRIM-2013-Std" ]; then
                echo "Extraction created SRIM-2013-Std directory, moving contents..."
                mv SRIM-2013-Std/* .
                rmdir SRIM-2013-Std
              elif [ ! -f "SRIM.exe" ]; then
                echo "WARNING: SRIM.exe not found, files may have extracted elsewhere"
                fi

              if [ -f "SRIM-Setup/MSVBvm50.exe" ]; then
                echo "Installing Visual Basic 5.0 Runtime..."
                ${wine}/bin/wine "SRIM-Setup/MSVBvm50.exe" 2>&1 || {
                  echo "VB runtime install had issues, continuing..."
                }
                sleep 3
              else
                echo "MSVBvm50.exe not found"
                fi

              if [ -d "SRIM-Setup" ]; then
                for ocx in SRIM-Setup/*.ocx; do
                  if [ -f "$ocx" ]; then
                    name=$(basename "$ocx")
                    echo "Registering $name"
                    ${wine}/bin/wine regsvr32 /s "$ocx" 2>&1 || true
                  fi
                done
              fi
              
              if [ -f "SRIM.exe" ]; then
                echo "Installation successful!"
                ls -lh SRIM.exe
              else
                echo "ERROR: SRIM.exe not found"
                exit 1
              fi
              
            popd
          '';
        };
        srim_desktop = pkgs.makeDesktopItem {
          name = "SRIM";
          desktopName = "SRIM";
          type = "Application";
          exec = "${srim_bin}/bin/SRIM";
        };
        srim = pkgs.symlinkJoin {
          name = "SRIM";
          paths = [ srim_bin srim_desktop ];
        };
      in {
        packages = {
          srim = srim;
          default = srim;
        };
      });
}
