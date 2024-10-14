{
  description = "Zorsh - simple zombie game";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  outputs = { nixpkgs, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      xDeps = with pkgs.xorg; [ libXcursor libXi libXrandr libXinerama];
      wayDeps = with pkgs; [ wayland libxkbcommon libdecor wayland-scanner ];
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        EM_CONFIG = pkgs.writeText ".emscripten" ''
          LLVM_ROOT = '${pkgs.emscripten.llvmEnv}/bin'
          BINARYEN_ROOT = '${pkgs.binaryen}'
          NODE_JS = '${pkgs.nodejs}/bin/node'
        '';
        buildInputs = [ pkgs.libGL pkgs.zig pkgs.zls ] ++ wayDeps ++ xDeps;
      };
    };
}
