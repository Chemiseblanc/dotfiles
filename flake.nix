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
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nix-darwin,
      nix-homebrew,
      ...
    }:
    let
      mkHome =
        {
          system,
          username,
          homeDirectory,
          configurationName,
          hostModule,
          extraModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config = nixpkgsConfig;
          };
          modules = [
            ./common
            ./platforms/linux
            hostModule
            {
              home = { inherit username homeDirectory; };
              home.sessionVariables.DOTFILES_CONFIG = configurationName;
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
          configurationName,
          hostModule,
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./platforms/darwin
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
            {
              nixpkgs.hostPlatform = system;
              nixpkgs.config = nixpkgsConfig;
              # Lix is installed externally; nix-darwin must not take it over.
              nix.enable = false;
              system.primaryUser = username;
              users.users.${username}.home = homeDirectory;
              nix-homebrew = {
                enable = true;
                enableRosetta = system == "aarch64-darwin";
                user = username;
                autoMigrate = true;
              };
              # Do not casually change after the first activation.
              system.stateVersion = 5;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = {
                  imports = [
                    ./common
                    ./platforms/darwin/home.nix
                  ];
                  home = { inherit username homeDirectory; };
                  home.sessionVariables.DOTFILES_CONFIG = configurationName;
                };
              };
            }
            hostModule
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
          configurationName = "example-darwin-aarch64";
          hostModule = ./hosts/example-darwin-aarch64.nix;
        };
      };
      homeConfigurations = {
        "example@linux-x86_64" = mkHome {
          system = "x86_64-linux";
          username = "example";
          homeDirectory = "/home/example";
          configurationName = "example@linux-x86_64";
          hostModule = ./hosts/example-linux-x86_64.nix;
        };
        "example@linux-aarch64" = mkHome {
          system = "aarch64-linux";
          username = "example";
          homeDirectory = "/home/example";
          configurationName = "example@linux-aarch64";
          hostModule = ./hosts/example-linux-aarch64.nix;
        };
      };
    };
}
