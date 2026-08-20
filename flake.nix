{
  description = "SISAR cluster configuration (flake-based)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";

    # Colmena como input: necesario para la salida colmenaHive (ver abajo).
    # A propósito NO se hace inputs.nixpkgs.follows: así se aprovecha la caché
    # binaria de colmena en vez de recompilarla desde el fuente.
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Overlays y config de nixpkgs se definen ACÁ, una sola vez, y no dentro
      # de los módulos.
      #
      # Motivo: colmena pasa `meta.nixpkgs` a cada nodo como `nixpkgs.pkgs`, y
      # el módulo nixpkgs de NixOS prohíbe combinar `nixpkgs.pkgs` con
      # `nixpkgs.overlays` o `nixpkgs.config` (falla la assertion "Your system
      # configures nixpkgs with an externally created instance"). Por eso el
      # antiguo modules/unstable.nix y el `nixpkgs.config.allowUnfree` de
      # common.nix se movieron hasta acá.
      overlays = [
        inputs.rust-overlay.overlays.default

        # pkgs.unstable.*  (reemplaza a modules/unstable.nix)
        (final: _: {
          unstable = import inputs.nixpkgs-unstable {
            inherit (final.stdenv.hostPlatform) system;
            inherit (final) config;
          };
        })
      ];

      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };

      # Claves públicas autorizadas para desplegar (usuario `sisar` en los 6
      # hosts). Se generan en la máquina DESDE la que se corre colmena:
      #   ssh-keygen -t ed25519 -C "usuario@equipo"
      #   cat ~/.ssh/id_ed25519.pub
      #
      # Pegá la línea completa, incluido el "ssh-ed25519 " del principio.
      # Va acá y no en modules/ssh.nix: ese módulo la recibe por specialArgs.
      deployKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM5OAhuIy4cS91dCu1KOOLlHl+EXmPQx9mpzNKUbcdCo sisar@sisar-nfs"
      ];

      hostNames = [
        "sisar-nfs"
        "sisar1"
        "sisar2"
        "sisar3"
        "sisar4"
        #"sisar5"
      ];

      # Módulos de un host. Se reutiliza para nixosConfigurations (rebuild
      # local) y para colmena (despliegue remoto), así ambas rutas de
      # evaluación no pueden divergir.
      hostModules = hostName: [ ./hosts/${hostName} ];

      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          specialArgs = {
            inherit inputs deployKeys;
          };
          modules = hostModules hostName;
        };

      # IPs de la LAN, usadas por hosts-lan.nix (dentro de cada sistema) y acá
      # por colmena, para saber a qué host conectarse por SSH.
      lan = {
        sisar-nfs = "192.168.0.241";
        sisar1 = "192.168.0.242";
        sisar2 = "192.168.0.243";
        sisar3 = "192.168.0.244";
        sisar4 = "192.168.0.245";
        # sisar5 = "192.168.0.225";
      };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost;

      # Colmena evalúa esta salida con `nix eval`.
      #
      # Sin ella cae al evaluador viejo (nix-instantiate + builtins.getFlake),
      # que en Nix 2.21+ falla con:
      #   error: cannot update unlocked flake input 'hive' in pure mode
      # Ver https://github.com/zhaofengli/colmena/issues/259
      colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;

      # `nix develop` en este directorio deja colmena (y utilidades de deploy)
      # en el PATH, con la versión que fija flake.lock. Evita depender de que
      # esté instalado en la máquina desde la que se despliega.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          # La colmena del input, no la de nixpkgs: la salida colmenaHive
          # requiere una versión que use el evaluador nuevo.
          inputs.colmena.packages.${system}.colmena
          pkgs.nixfmt-rfc-style
          pkgs.nix-output-monitor
        ];
      };

      # `colmena apply switch` despliega esto a toda la flota (o a un
      # subconjunto con --on / --on @tag) desde una sola máquina.
      colmena =
        {
          meta = {
            nixpkgs = pkgs;
            specialArgs = {
              inherit inputs deployKeys;
            };
          };

          # Se mezcla en TODOS los nodos.
          #
          # targetUser = "root": las claves de `deployKeys` se autorizan para
          # root en modules/ssh.nix, y root ya está en AllowUsers con
          # PermitRootLogin = "prohibit-password" (sólo clave, nunca password).
          # Siendo root, colmena no necesita escalar privilegios con sudo.
          #
          # Para desplegar como `sisar` en su lugar: cambiar targetUser acá,
          # y en modules/ssh.nix mover deployKeys al usuario sisar y
          # descomentar la regla de sudo NOPASSWD.
          defaults =
            { name, ... }:
            {
              deployment = {
                targetHost = lan.${name};
                targetUser = "root";
                targetPort = 22;
              };
            };
        }
        // nixpkgs.lib.genAttrs hostNames (
          hostName:
          {
            imports = hostModules hostName;
          }
          // (
            if hostName == "sisar-nfs" then
              { deployment.tags = [ "server" ]; }
            else
              { deployment.tags = [ "client" ]; }
          )
        );
    };
}
