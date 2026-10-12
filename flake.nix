{
  description = "SISAR cluster configuration (flake-based)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";

    zen-browser.url = "github:youwen5/zen-browser-flake";

    # El código de SISAR: paquetes (sisar-server, sisar-scheduler, los runners)
    # y los módulos de NixOS que los configuran.
    #
    # Los módulos viven en ese repo y no acá a propósito: generan el config.toml
    # que leen los binarios, y mientras estuvieron separados nadie pudo probar
    # el par. sisar-server.nix emitía `server.listen` mientras ServerConfig leía
    # `host` y `port`, serde ignoraba la clave desconocida y el servidor
    # escuchaba en 127.0.0.1 sin un solo error. Ahora el flake de SISAR tiene un
    # check que le pasa el TOML generado a los binarios.
    # git+ssh y no github:, a propósito. El repositorio es privado, y el
    # fetcher `github:` resuelve por la API REST de GitHub, que desde Nix va sin
    # credenciales: un repo privado le devuelve 404, indistinguible de uno que
    # no existe. Con git+ssh usa git, que ya tiene la clave con la que empujás.
    #
    # El ref es explícito para que un cambio de rama por defecto en GitHub no
    # mueva lo que despliega esta configuración.
    sisar.url = "git+ssh://git@github.com/veratomas/sisar?ref=0.3.0";

    # Fuente del backend del sitio web (modules/isat.nix). Es el código Rust
    # de /var/www/sisar/isat-server.
    #
    # `path:` y no `git+ssh:` como el input `sisar` de arriba porque ese
    # directorio todavía NO es un repo git: es una copia desempaquetada de
    # isat-src.zip. Apunta al subdirectorio isat-server/ y no a la raíz del
    # proyecto a propósito — así editar el frontend (que es lo que se está
    # tocando todos los días) no invalida el lock del input; sólo lo hace un
    # cambio en el código Rust, y ahí toca `nix flake update isat-src`.
    #
    # PENDIENTE: cuando el código de ISAT tenga su repo, esto pasa a ser un
    # `git+ssh://...?ref=<tag>` igual que `sisar`, y deja de depender de un
    # directorio mutable fuera del flake.
    isat-src = {
      url = "path:/var/www/sisar/isat-server";
      flake = false;
    };

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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN29w53IjJVwhY7BG9tkoZEYb9DEGc/812dxYJ2kJcvz veratomas.sf@gmail.com"
      ];

      # Fuente única de la lista de hosts, compartida con modules/hosts-lan.nix
      # y modules/storage-nodes.nix. Agregar un nodo es una línea en nodes.nix.
      nodes = import ./nodes.nix;

      hostNames = builtins.attrNames (nodes.server // nodes.compute);

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
      # por colmena, para saber a qué host conectarse por SSH. Salen de
      # nodes.nix, igual que hostNames.
      lan = nodes.server // nodes.compute;
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
            if hostName == "sisar-server" then
              { deployment.tags = [ "server" ]; }
            else
              { deployment.tags = [ "client" ]; }
          )
        );
    };
}
