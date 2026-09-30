# PostgreSQL — SERVIDOR (host: sisar-server solamente).
#
# La base `sisar` vive únicamente acá. Los nodos no corren PostgreSQL: se
# conectan por TCP a sisar-server:5432 (ver postgresql-client.nix). Una sola
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
    # Desde sisar-server, el usuario `sisar` entra como rol `sisar` sin
    # contraseña, y `postgres` como superusuario. Si algo en sisar-server se
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

  # ── Esperar la IP de la LAN antes de arrancar ──────────────────────────────
  #
  # `listen_addresses` nombra una IP concreta, y PostgreSQL la bindea UNA sola
  # vez, al arrancar. Si en ese momento la IP todavía no está asignada, no
  # falla: loguea
  #
  #   could not bind IPv4 address "192.168.0.241": Cannot assign requested address
  #   WARNING: could not create listen socket for "192.168.0.241"
  #
  # sigue adelante escuchando SÓLO en localhost, y systemd lo deja en
  # "active (running)". Impecable a la vista, inalcanzable para los nodos.
  #
  # Pasó en el arranque del 2026-09-29: los schedulers de los cuatro nodos en
  # bucle de reinicio con "pool timed out while waiting for an open connection"
  # mientras `systemctl status postgresql` mostraba todo bien. Costó encontrarlo
  # porque el síntoma aparece en los nodos y la causa está en el servidor.
  #
  # network-online.target por sí solo no alcanza: garantiza que hay red, no que
  # ESTA dirección esté puesta en la interfaz. Así que se espera explícitamente.
  #
  # Y si no aparece, se aborta en vez de arrancar a medias: un PostgreSQL caído
  # se nota enseguida, uno escuchando sólo en localhost no.
  systemd.services.postgresql = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.iproute2 ];

    # mkBefore: esto va ANTES del preStart del módulo de nixpkgs (initdb, etc.),
    # no en lugar de él. Ojo con `exit 0` acá: cortaría el resto del preStart.
    preStart = lib.mkBefore ''
      lista=
      for _ in $(seq 1 90); do
        if ip -4 addr show to ${myIp}/32 | grep -q inet; then
          lista=1
          break
        fi
        sleep 1
      done
      if [ -z "$lista" ]; then
        echo "la IP ${myIp} no apareció en 90s: se aborta el arranque en lugar" \
             "de quedar escuchando sólo en localhost, que dejaría a los nodos" \
             "sin base de datos sin que se note" >&2
        exit 1
      fi
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
