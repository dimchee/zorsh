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
        buildInputs = [ pkgs.libGL pkgs.zig pkgs.zls ] ++ wayDeps ++ xDeps;
      };
    };
}
