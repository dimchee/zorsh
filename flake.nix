{
  description = "Zorsh flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { nixpkgs, ... }: 
  let 
    pkgs = import nixpkgs { system = "x86_64-linux"; };
  in {
    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = with pkgs; [ 
        zig zls
        xorg.libXcursor
        xorg.libXi
        xorg.libXrandr
        xorg.libXinerama
        libGL
      ];
      LIBGL_ALWAYS_INDIRECT=0;
    };
  };
}
