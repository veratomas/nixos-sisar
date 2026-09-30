# El scheduler de un nodo de cómputo.
#
# Trae el módulo del flake de SISAR y le aplica todo lo que vale para la flota,
# desde sisar-cluster.nix. Un host sólo declara lo que es suyo:
#
#   imports = [ ../../modules/sisar-node.nix ];
#   services.sisar.scheduler = {
#     enable = true;
#     resources = { cpuCores = 8; ramGb = 16.0; };
#   };
#
# Todo se define con mkDefault, así que un nodo puede apartarse de la flota
# cuando hace falta — un nodo con otro disco y otro minFreeGb, por ejemplo —
# sin que deje de haber un solo lugar donde está el valor común.
#
# `images`, `userTiers` y `workflows` son los que conviene NO apartar: el
# servidor y los nodos tienen que coincidir en los dos primeros, y que
# workflows.toml resuelva al mismo path del store en los seis hosts es lo que
# hace visible que la flota está de acuerdo sobre lo que cuesta cada etapa.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cluster = import ../sisar-cluster.nix;
in
{
  imports = [ inputs.sisar.nixosModules.scheduler ];

  # ── Recuperación del scheduler tras un arranque sin NFS ────────────────────
  #
  # El problema, visto de verdad en la migración del 2026-09-30: si un nodo
  # arranca mientras sisar-server no exporta, /srv/sisar no se monta, y como
  # sisar-scheduler declara RequiresMountsFor sobre /srv/sisar y sobre su
  # propio jobs/, systemd lo aborta con "Dependency failed".
  #
  # Y ahí se queda. `Restart=` NO cubre este caso: sólo actúa cuando el
  # proceso arrancó y murió, y acá nunca arrancó. El nodo queda arriba, sano y
  # silencioso, con el scheduler apagado — que es la peor forma de fallar,
  # porque no se nota hasta que alguien mira por qué no toma trabajo.
  #
  # No se arregla relajando la dependencia: un scheduler corriendo sin
  # /srv/sisar montado escribiría abajo del punto de montaje vacío, que es
  # exactamente lo que RequiresMountsFor está evitando. Así que la dependencia
  # queda dura y lo que se agrega es un reintento.
  systemd.services.sisar-scheduler-retry = {
    description = "Reintenta arrancar sisar-scheduler si quedó caído por dependencias";
    path = with pkgs; [
      systemd
      coreutils
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      # `disable` o `mask` tienen que poder apagar el scheduler de verdad: si
      # no está enabled, no insistimos. Un `systemctl stop` suelto, en cambio,
      # SÍ se revierte — en un nodo de cómputo el scheduler apagado a mano y
      # olvidado es un problema, no un estado válido. Para bajarlo en serio:
      # systemctl disable --now sisar-scheduler
      [ "$(systemctl is-enabled sisar-scheduler 2>/dev/null)" = "enabled" ] || exit 0

      case "$(systemctl is-active sisar-scheduler 2>/dev/null)" in
        active | activating | reloading) exit 0 ;;
      esac

      # Antes de insistir, comprobar que el share responde. Sin esto el
      # arranque volvería a fallar por lo mismo y llenaríamos el journal de
      # intentos idénticos cada pocos minutos. El timeout es por los montajes
      # `hard`: si el servidor está caído, el acceso espera, no falla rápido.
      if ! timeout 15 ls /srv/sisar >/dev/null 2>&1; then
        echo "/srv/sisar todavía no responde; no se intenta arrancar el scheduler"
        exit 0
      fi

      echo "sisar-scheduler caído y /srv/sisar disponible: arrancando"
      systemctl start sisar-scheduler
    '';
  };

  systemd.timers.sisar-scheduler-retry = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # OnBootSec por el arranque en frío de todo el cluster: si el nodo gana
      # la carrera contra sisar-server, el primer reintento lo acomoda.
      OnBootSec = "3min";
      OnUnitInactiveSec = "5min";
      Unit = "sisar-scheduler-retry.service";
    };
  };

  services.sisar.scheduler = {
    package = lib.mkDefault inputs.sisar.packages.x86_64-linux.sisar-scheduler;

    databaseUrl = lib.mkDefault cluster.databaseUrl;
    centralRoot = lib.mkDefault cluster.centralRoot;

    netrcFile = lib.mkDefault cluster.netrcFile;
    cdsapircFile = lib.mkDefault cluster.cdsapircFile;

    images = lib.mapAttrs (_: v: lib.mkDefault v) cluster.images;

    userTiers = lib.mkDefault cluster.userTiers;
    workflows = lib.mkDefault cluster.workflows;
  };
}
