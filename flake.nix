{
  description = "Cross-platform Lix, Home Manager, and nix-darwin dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nix-darwin,
      ...
    }:
    let
      mkHome =
        {
          system,
          username,
          homeDirectory,
          extraModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; };
          modules = [
            ./home/default.nix
            ./hosts/linux/default.nix
            ./home/linux.nix
            {
              home = { inherit username homeDirectory; };
            }
          ]
          ++ extraModules;
          extraSpecialArgs = { inherit inputs; };
        };
      mkDarwin =
        {
          system,
          username,
          homeDirectory,
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/darwin/default.nix
            ./darwin/default.nix
            home-manager.darwinModules.home-manager
            {
              nixpkgs.hostPlatform = system;
              # Lix is installed externally; nix-darwin must not take it over.
              nix.enable = false;
              system.primaryUser = username;
              users.users.${username}.home = homeDirectory;
              # Do not casually change after the first activation.
              system.stateVersion = 5;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = {
                  imports = [
                    ./home/default.nix
                    ./home/darwin.nix
                  ];
                  home = { inherit username homeDirectory; };
                };
              };
            }
          ];
        };
    in
    {
      # Rename/copy these examples to your LocalHostName or user@short-hostname.
      darwinConfigurations = {
        example-darwin-aarch64 = mkDarwin {
          system = "aarch64-darwin";
          username = "example";
          homeDirectory = "/Users/example";
        };
      };
      homeConfigurations = {
        "example@linux-x86_64" = mkHome {
          system = "x86_64-linux";
          username = "example";
          homeDirectory = "/home/example";
        };
        "example@linux-aarch64" = mkHome {
          system = "aarch64-linux";
          username = "example";
          homeDirectory = "/home/example";
        };
      };
    };
}
