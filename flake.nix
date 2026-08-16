{
  description = "SISAR cluster configuration (flake-based, headless)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Módulo compartido por todos los hosts: habilita el overlay de rust-overlay
      overlaysModule = (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ inputs.rust-overlay.overlays.default ];
        }
      );

      hostNames = [
        "sisar-nfs"
        "sisar1"
        "sisar2"
        "sisar3"
        "sisar4"
        "sisar5"
      ];

      # Lista de módulos de un host. Se reutiliza tanto para nixosConfigurations
      # (nixos-rebuild local, por si un equipo se despliega a mano) como para
      # colmena (despliegue remoto de toda la flota), para que ambas rutas de
      # evaluación no puedan divergir entre sí.
      hostModules = hostName: [
        overlaysModule
        ./hosts/${hostName}
      ];

      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
          };
          modules = hostModules hostName;
        };

      # IPs de la LAN, usadas por hosts-lan.nix (dentro de cada sistema) y acá
      # por colmena, para saber a qué host conectarse por SSH.
      lan = {
        sisar-nfs = "192.168.0.220";
        sisar1 = "192.168.0.221";
        sisar2 = "192.168.0.222";
        sisar3 = "192.168.0.223";
        sisar4 = "192.168.0.224";
        sisar5 = "192.168.0.225";
      };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost;

      # `colmena apply switch` despliega esto a toda la flota (o a un subconjunto
      # con --on / --on @tag) desde una sola máquina. No hace falta agregar
      # colmena como input: el binario (nixpkgs#colmena) lee este atributo
      # directamente al correr `colmena apply` en este directorio.
      colmena =
        {
          meta = {
            nixpkgs = import nixpkgs { inherit system; };
            specialArgs = {
              inherit inputs;
            };
          };

          # Se mezcla en TODOS los nodos. targetUser = "root" requiere el ajuste
          # de ssh.nix (AllowUsers) descrito en el chat/README; alternativa:
          # targetUser = "sisar" + sudo NOPASSWD.
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
