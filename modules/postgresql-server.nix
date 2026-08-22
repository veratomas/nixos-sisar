# PostgreSQL — SERVIDOR (host: sisar-nfs solamente).
#
# La base `sisar` vive únicamente acá. Los nodos no corren PostgreSQL: se
# conectan por TCP a sisar-nfs:5432 (ver postgresql-client.nix). Una sola
# copia de los datos, sin réplicas que sincronizar.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Tiene que coincidir con hosts-lan.nix.
  lanCidr = "192.168.0.0/24";
  myIp = "192.168.0.241";
in
{
  services.postgresql = {
    enable = true;
    enableTCPIP = true;

    ensureDatabases = [ "sisar" ];

    # ensureDBOwnership exige que el rol se llame igual que la base.
    # OJO: crea el rol pero NO le pone contraseña — eso se hace a mano una
    # vez (ver la guía). Sin contraseña, las conexiones por red fallan con
    # "password authentication failed", que es el comportamiento correcto.
    ensureUsers = [
      {
        name = "sisar";
        ensureDBOwnership = true;
      }
    ];

    settings = {
      # Sólo loopback y la IP de la LAN. No "*": sin esto quedaría escuchando
      # también en cualquier interfaz futura (Tailscale, por ejemplo).
      listen_addresses = lib.mkForce "localhost,${myIp}";

      password_encryption = "scram-sha-256";

      # Cuatro nodos con varios workers cada uno; el default de 100 queda
      # corto y el síntoma es "too many clients already" a mitad de un job.
      max_connections = 200;
    };

    # Reemplaza al `local all all trust` anterior.
    #
    # `peer` en local: el usuario del sistema tiene que coincidir con el rol.
    # Desde sisar-nfs, el usuario `sisar` entra como rol `sisar` sin
    # contraseña, y `postgres` como superusuario. Si algo en sisar-nfs se
    # conecta localmente con OTRO rol, va a empezar a fallar — en ese caso
    # volvé a `trust` en la línea local.
    #
    # `scram-sha-256` desde la LAN: contraseña obligatoria, hasheada. Sólo el
    # rol `sisar` sobre la base `sisar`; no se expone `postgres` por red.
    authentication = lib.mkOverride 10 ''
      #type  database  DBuser  origen          auth-method
      local  all       all                     peer
      host   all       all     127.0.0.1/32    scram-sha-256
      host   all       all     ::1/128         scram-sha-256
      host   sisar     sisar   ${lanCidr}      scram-sha-256
    '';
  };

  # Backups diarios de la base. Van al disco de datos, así que quedan en el
  # disco grande y no en el de sistema. NO reemplazan un backup fuera de la
  # máquina: si se muere ese disco, se van los datos y los backups juntos.
  services.postgresqlBackup = {
    enable = true;
    databases = [ "sisar" ];
    location = "/srv/sisar/backups/postgres";
    startAt = "*-*-* 03:00:00";
  };

  systemd.tmpfiles.rules = [
    "d /srv/sisar/backups          0750 postgres postgres -"
    "d /srv/sisar/backups/postgres 0750 postgres postgres -"
  ];

  # El backup escribe en el disco de datos: no puede correr antes del montaje.
  systemd.services.postgresqlBackup-sisar.unitConfig.RequiresMountsFor = "/srv/sisar";

  # 5432 abierto a la LAN. La restricción real por origen la hace pg_hba
  # (arriba): el firewall no distingue rol ni base.
  networking.firewall.allowedTCPPorts = [ 5432 ];
}
