# SRIM-nix!
Declarative packaging for SRIM (The Stopping and Range of Ions in Matter - https://www.srim.org/) using nix flakes + wrapWineby lucasew (https://github.com/lucasew/nixcfg/blob/e542e743774f499f996a4f886a8d4a4133fce258/packages/wrapWine.nix). Since it's packaged with nix, it will just work!

## Usage
### Standalone
```
git clone https://github.com/ewtodd/SRIM-nix.git
cd SRIM-nix
nix build
./result/bin/SRIM
```
### NixOS Configuration
```
# in your flake.nix
inputs = { ...
    SRIM.url = "github:ewtodd/SRIM-nix";
};
...
# in your configuration.nix
{ inputs, ...}: let SRIM = inputs.SRIM.packages."x86_64-linux".default;
in {
  ...
environment.systemPackages = [ ... SRIM ... ];
...
}
```

