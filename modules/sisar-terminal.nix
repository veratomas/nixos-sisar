# modules/sisar-terminal.nix
#
# La identidad de SISAR en la terminal: esquema y perfil de Konsole, tema de
# kitty, y tema de colores + bienvenida para Nushell.
#
# Se importa desde base.nix, o sea que va a los seis hosts. El tema de Nushell
# y la bienvenida valen igual entrando por SSH a un nodo que en el escritorio
# de sisar-server — de hecho es donde más sirven, porque el banner dice de una
# en qué host estás parado. Konsole y kitty se instalan sólo donde hay Plasma
# (plasma6.nix): en un nodo headless serían dos paquetes al pedo.
#
# El bloque de estado NO lleva una lista escrita a mano. `sisar.terminal.servicios`
# se deriva de lo que cada host tiene habilitado: un nodo de cómputo muestra su
# scheduler y docker, sisar-server muestra la API, PostgreSQL y el export NFS.
# Habilitar un servicio en un host lo agrega al banner sin tocar este archivo.
#
# Lo que vigila el banner se pasa por `environment.variables` y no incrustado en
# el .nu: así el archivo de Nushell es el mismo derivation en los seis hosts y
# sólo cambian tres variables.

{ config, lib, pkgs, ... }:

let
  cfg = config.sisar.terminal;

  # ---------------------------------------------------------------- paleta --
  # Los colores del manual de marca, ajustados a pantalla: el azul y el gris se
  # aclararon para que todo el texto quede sobre 4,5:1 contra el fondo abismo.
  sisar = {
    abismo    = "#071A22";       # fondo
    profundo  = "#0E3145";       # barras y fondos secundarios
    seleccion = "#143B4F";
    texto     = "#E3EAEC";
    hueso     = "#F4F7F8";
    cian      = "#29C7D6";       # cursor y acento
    cianClaro = "#7FE3EC";
    gris      = "#5C6B72";
    grisClaro = "#C7D0D3";
    rojo      = "#E2574C";
    verde     = "#3FB27F";
    amarillo  = "#D8A24A";
    azul      = "#4287D0";
    violeta   = "#9A7AD1";
  };

  # ------------------------------------------------------------- konsole ----
  colorscheme = pkgs.writeText "SISAR.colorscheme" ''
    [General]
    Description=SISAR
    Opacity=1
    Wallpaper=
    ColorRandomization=false

    [Background]
    Color=7,26,34

    [BackgroundIntense]
    Color=20,59,79

    [BackgroundFaint]
    Color=7,26,34

    [Foreground]
    Color=227,234,236

    [ForegroundIntense]
    Color=244,247,248
    Bold=true

    [ForegroundFaint]
    Color=116,133,141

    [Color0]
    Color=14,32,41

    [Color0Intense]
    Color=116,133,141

    [Color0Faint]
    Color=8,19,25

    [Color1]
    Color=226,87,76

    [Color1Intense]
    Color=240,119,108

    [Color1Faint]
    Color=140,53,47

    [Color2]
    Color=63,178,127

    [Color2Intense]
    Color=99,207,155

    [Color2Faint]
    Color=39,110,78

    [Color3]
    Color=216,162,74

    [Color3Intense]
    Color=240,192,105

    [Color3Faint]
    Color=133,100,45

    [Color4]
    Color=66,135,208

    [Color4Intense]
    Color=90,147,216

    [Color4Faint]
    Color=40,83,128

    [Color5]
    Color=154,122,209

    [Color5Intense]
    Color=183,154,230

    [Color5Faint]
    Color=95,75,129

    [Color6]
    Color=41,199,214

    [Color6Intense]
    Color=127,227,236

    [Color6Faint]
    Color=25,123,132

    [Color7]
    Color=199,208,211

    [Color7Intense]
    Color=244,247,248

    [Color7Faint]
    Color=123,128,130
  '';

  profile = pkgs.writeText "SISAR.profile" ''
    [General]
    Name=SISAR
    Parent=FALLBACK/
    TerminalColumns=110
    TerminalRows=32

    [Appearance]
    ColorScheme=SISAR
    Font=${cfg.fuente}
    UseFontLineCharacters=true

    [Cursor Options]
    CursorShape=0
    UseCustomCursorColor=true
    CustomCursorColor=41,199,214
    CustomCursorTextColor=7,26,34

    [Scrolling]
    HistoryMode=2

    [Terminal Features]
    BlinkingCursorEnabled=false
  '';

  # Konsole busca esquemas y perfiles en $XDG_DATA_DIRS/konsole, así que alcanza
  # con un paquete que los deje en share/konsole. Nada se escribe en el home.
  sisar-konsole = pkgs.runCommand "sisar-konsole-theme" { } ''
    mkdir -p $out/share/konsole
    cp ${colorscheme} $out/share/konsole/SISAR.colorscheme
    cp ${profile}     $out/share/konsole/SISAR.profile
  '';
in
{
  options.sisar.terminal = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tema e identidad de SISAR en la terminal.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.2.0";
      description = "Versión que muestra la línea de datos del banner.";
    };

    servicios = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        lib.optional (config.services.sisar.server.enable or false) "sisar-server"
        ++ lib.optional (config.services.sisar.scheduler.enable or false) "sisar-scheduler"
        ++ lib.optional (config.services.postgresql.enable or false) "postgresql"
        ++ lib.optional (config.services.nfs.server.enable or false) "nfs-server"
        ++ lib.optional (config.virtualisation.docker.enable or false) "docker";
      defaultText = lib.literalExpression "los servicios de SISAR habilitados en este host";
      description = "Unidades de systemd que el banner consulta con systemctl is-active.";
    };

    discos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/" ];
      example = [
        "/"
        "/srv/sisar"
      ];
      description = ''
        Puntos de montaje cuyo uso muestra el banner.

        Por defecto sólo la raíz, que es local y responde siempre. /srv/sisar se
        deja afuera a propósito: en los nodos es NFS montado hard con timeo=600,
        y aunque el chequeo corre con `timeout 1` y no llega a colgar la terminal,
        con el servidor caído la línea desaparecería sin explicar por qué.
        Agregalo si querés verlo en sisar-server, donde es un disco local.
      '';
    };

    jobs = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/sisar/jobs";
      description = ''
        Directorio cuyas entradas cuenta el banner como "jobs en cola".
        null lo desactiva. En un nodo conviene el jobs local (/var/lib/sisar/jobs)
        y no el central por NFS, por el mismo motivo que `discos`.
      '';
    };

    fuente = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
      description = ''
        Fuente del perfil de Konsole, en el formato de QFont. La de fábrica es
        JetBrainsMono Nerd Font, que plasma6.nix ya instala y que tiene los
        caracteres de medio bloque (▀ ▄ █) con los que está dibujado el isotipo.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Konsole y kitty sólo donde hay escritorio.
    environment.systemPackages =
      lib.optional config.services.desktopManager.plasma6.enable sisar-konsole;

    environment.etc = lib.mkMerge [
      {
        # La biblioteca: tema de colores, prompt y los bloques del banner.
        "nushell/sisar-theme.nu".text = ''
          # Tema de colores SISAR para Nushell.
          #
          # Uso (en tu config.nu):
          #     use /etc/nushell/sisar-theme.nu *
          #     ''$env.config.color_config = (sisar-tema)
          #     if ''$nu.is-interactive { sisar-bienvenida }       # banner al abrir
          #     ''$env.config.show_banner = false                   # apaga el de Nushell
          #     ''$env.PROMPT_COMMAND = {|| sisar-prompt }          # prompt opcional
          #     ''$env.PROMPT_INDICATOR = ''$"(ansi -e '38;2;41;199;214m')> (ansi reset)"

          export def sisar-colores [] {
            {
              abismo: "#071A22"
              profundo: "#0E3145"
              cian: "#29C7D6"
              cian_claro: "#7FE3EC"
              hueso: "#F4F7F8"
              texto: "#E3EAEC"
              gris: "#5C6B72"
              gris_claro: "#C7D0D3"
              rojo: "#E2574C"
              verde: "#3FB27F"
              amarillo: "#D8A24A"
              azul: "#4287D0"
              violeta: "#9A7AD1"
            }
          }

          export def sisar-tema [] {
            {
              separator: "#74858D"
              leading_trailing_space_bg: { attr: n }
              header: { fg: "#29C7D6" attr: b }
              empty: "#4287D0"
              bool: "#3FB27F"
              int: "#E3EAEC"
              filesize: "#D8A24A"
              duration: "#D8A24A"
              date: "#9A7AD1"
              range: "#E3EAEC"
              float: "#E3EAEC"
              string: "#E3EAEC"
              nothing: "#74858D"
              binary: "#9A7AD1"
              cell-path: "#C7D0D3"
              row_index: { fg: "#74858D" attr: b }
              record: "#C7D0D3"
              list: "#C7D0D3"
              block: "#C7D0D3"
              hints: "#5C6B72"
              search_result: { fg: "#071A22" bg: "#29C7D6" }

              shape_binary: { fg: "#B79AE6" attr: b }
              shape_block: { fg: "#5A93D8" attr: b }
              shape_bool: "#7FE3EC"
              shape_closure: { fg: "#63CF9B" attr: b }
              shape_custom: "#3FB27F"
              shape_datetime: { fg: "#B79AE6" attr: b }
              shape_directory: "#29C7D6"
              shape_external: "#7FE3EC"
              shape_externalarg: { fg: "#63CF9B" attr: b }
              shape_filepath: "#29C7D6"
              shape_flag: { fg: "#5A93D8" attr: b }
              shape_float: { fg: "#B79AE6" attr: b }
              shape_garbage: { fg: "#F4F7F8" bg: "#E2574C" attr: b }
              shape_globpattern: { fg: "#7FE3EC" attr: b }
              shape_int: { fg: "#B79AE6" attr: b }
              shape_internalcall: { fg: "#7FE3EC" attr: b }
              shape_keyword: { fg: "#B79AE6" attr: b }
              shape_list: { fg: "#7FE3EC" attr: b }
              shape_literal: "#4287D0"
              shape_match_pattern: "#3FB27F"
              shape_matching_brackets: { attr: u }
              shape_nothing: "#7FE3EC"
              shape_operator: "#D8A24A"
              shape_pipe: { fg: "#B79AE6" attr: b }
              shape_range: { fg: "#F0C069" attr: b }
              shape_record: { fg: "#7FE3EC" attr: b }
              shape_redirection: { fg: "#B79AE6" attr: b }
              shape_signature: { fg: "#63CF9B" attr: b }
              shape_string: "#3FB27F"
              shape_string_interpolation: { fg: "#7FE3EC" attr: b }
              shape_table: { fg: "#5A93D8" attr: b }
              shape_variable: "#9A7AD1"
              shape_vardecl: "#9A7AD1"
            }
          }

          # Prompt opcional:  usuario@host  ruta  (rama)
          export def sisar-prompt [] {
            let cian = (ansi -e '38;2;41;199;214m')
            let gris = (ansi -e '38;2;92;107;114m')
            let hueso = (ansi -e '38;2;199;208;211m')
            let amarillo = (ansi -e '38;2;216;162;74m')
            let ruta = (''$env.PWD | str replace (''$env.HOME? | default '/home') '~')
            let rama = (do -i { git rev-parse --abbrev-ref HEAD } | complete
                        | if ''$in.exit_code == 0 { ''$"(''$amarillo) \((''$in.stdout | str trim)\)" } else { "" })
            ''$"(''$cian)(sys host | get hostname)(''$gris):(''$hueso)(''$ruta)(''$rama)(ansi reset)"
          }

          # ============================================================== bienvenida ===
          # Lo que se ve al abrir la terminal, en tres bloques:
          #   1. sisar-logotipo   SISAR en ASCII, con la bajada
          #   2. sisar-isotipo    el domo con Sudamérica, el arco y el satélite
          #   3. sisar-datos + sisar-paleta + sisar-estado
          #
          # sisar-banner los imprime en ese orden. sisar-bienvenida es la que conviene
          # llamar desde config.nu: completa en la primera terminal de la sesión, una
          # línea en las siguientes.
          #
          # Qué muestra el bloque de estado sale del módulo de NixOS, por variables de
          # entorno, así que cada host trae lo suyo sin editar este archivo.

          def sisar-cfg [] {
            {
              version: (''$env.SISAR_TERM_VERSION? | default '0.2.0')
              servicios: (''$env.SISAR_TERM_SERVICIOS? | default ''' | split row ' ' | where {|x| ''$x != ''' })
              discos: (''$env.SISAR_TERM_DISCOS? | default '/' | split row ' ' | where {|x| ''$x != ''' })
              jobs: (''$env.SISAR_TERM_JOBS? | default ''')
            }
          }


          export def sisar-logotipo [] {
            let cian = (ansi -e '38;2;41;199;214m')
            let gris = (ansi -e '38;2;92;107;114m')
            let fin = (ansi reset)
            for l in [
              '   _____ _________ ___    ____',
              '  / ___//  _/ ___//   |  / __ \',
              '  \__ \ / / \__ \/ /| | / /_/ /',
              ' ___/ // / ___/ / ___ |/ _, _/',
              '/____/___//____/_/  |_/_/ |_|'
            ] { print ''$'(''$cian)(''$l)(''$fin)' }
            print ''$'(''$gris) Sistema Interferometrico SAR(''$fin)'
            print ''$'(''$gris) con Automatizacion y Reporte(''$fin)'
          }


          export def sisar-isotipo [] {
            let cian = (ansi -e '38;2;41;199;214m')
            let fin = (ansi reset)
            let w = (do -i { term size | get columns } | default 0)
            let ancho = (if ''$w < 20 { 100 } else { ''$w })
            let arte = if ''$ancho >= 96 {
              [
                '                           ███',
                '                   ▄▄▄▄▄▄   ███ ▄▄██▄',
                '            ▄▄▄▀▀▀▀▀    ▀▀▀▀▀███████▀',
                '         ▄▄▀▀              ███████▀',
                '       ▄▀                  ▀▀█ ▀██▄▀▄',
                '     ▄▀           ▄▄▄▄▄▄▄▄      ▀███ ▀▄',
                '   ▄█         ▄████▀ ▀▀▀█████▄        ▀█▄',
                '  ▄▀       ▄███████      ▀▀█████▄       █▄',
                ' ▄▀       ██████████▄     ▄██████▄       █▄',
                ' █       ████████████   ▄▄█████████       █',
                '█       █████████████ ▄▄████████████      ▀▄',
                '█      ▄█████████████▄██████████████       █',
                '█      ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀       █'
              ]
            } else {
              [
                '                   ██',
                '         ▄▄▄▀▀▀▀▀▀▄▄██████',
                '      ▄▀▀          █████',
                '    ▄▀              ▀ ▀██▀▄',
                '  ▄▀     ▄▄███▀▀▀███▄  ▀   █',
                ' ▄▀    ▄█████▄    ▀███▄     █',
                '▄▀    ▄████████  ▄██████     █',
                '█    ▄█████████▄█████████    ▀▄',
                '█    ████████████████████     █'
              ]
            }
            for l in ''$arte { print ''$'(''$cian)(''$l)(''$fin)' }
          }


          export def sisar-datos [] {
            let cian = (ansi -e '38;2;41;199;214m')
            let gris = (ansi -e '38;2;92;107;114m')
            let fin = (ansi reset)
            let host = (do -i { sys host | get hostname } | default ''')
            let fecha = (date now | format date '%d/%m/%Y %H:%M')
            print ''$'(''$gris) v((sisar-cfg).version) · (''$cian)(''$host)(''$gris) · (''$fecha)(''$fin)'
          }


          # Muestrario de los 16 colores, para comprobar de un vistazo que el perfil de
          # la terminal es el de SISAR y no el heredado de KDE.
          export def sisar-paleta [] {
            let c0 = (ansi -e '38;2;14;32;41m')
            let c1 = (ansi -e '38;2;226;87;76m')
            let c2 = (ansi -e '38;2;63;178;127m')
            let c3 = (ansi -e '38;2;216;162;74m')
            let c4 = (ansi -e '38;2;66;135;208m')
            let c5 = (ansi -e '38;2;154;122;209m')
            let c6 = (ansi -e '38;2;41;199;214m')
            let c7 = (ansi -e '38;2;199;208;211m')
            let b0 = (ansi -e '38;2;116;133;141m')
            let b1 = (ansi -e '38;2;240;119;108m')
            let b2 = (ansi -e '38;2;99;207;155m')
            let b3 = (ansi -e '38;2;240;192;105m')
            let b4 = (ansi -e '38;2;90;147;216m')
            let b5 = (ansi -e '38;2;183;154;230m')
            let b6 = (ansi -e '38;2;127;227;236m')
            let b7 = (ansi -e '38;2;244;247;248m')
            let gris = (ansi -e '38;2;92;107;114m')
            let fin = (ansi reset)
            print ''$' (''$gris)paleta  (''$c0)███ (''$c1)███ (''$c2)███ (''$c3)███ (''$c4)███ (''$c5)███ (''$c6)███ (''$c7)███(''$fin)'
            print ''$'         (''$b0)███ (''$b1)███ (''$b2)███ (''$b3)███ (''$b4)███ (''$b5)███ (''$b6)███ (''$b7)███(''$fin)'
          }


          # Estado del host. Cada chequeo se hace con `timeout 1` a propósito: /srv/sisar
          # es NFS con hard,timeo=600 y un statvfs sobre un export caído no devuelve — sin
          # el timeout, abrir una terminal en un nodo se colgaría hasta que volviera el
          # servidor. Si un chequeo no responde en un segundo, esa línea no aparece.
          export def sisar-estado [] {
            let cfg = (sisar-cfg)
            let verde = (ansi -e '38;2;63;178;127m')
            let amarillo = (ansi -e '38;2;216;162;74m')
            let rojo = (ansi -e '38;2;226;87;76m')
            let gris = (ansi -e '38;2;92;107;114m')
            let texto = (ansi -e '38;2;227;234;236m')
            let fin = (ansi reset)
            mut filas = []

            for s in ''$cfg.servicios {
              let r = (do -i { ^timeout 1 systemctl is-active ''$s | complete })
              let v = (if ''$r == null { ''' } else { ''$r.stdout | str trim })
              if ''$v != ''' {
                let col = (if ''$v == 'active' { ''$verde } else if ''$v == 'inactive' { ''$amarillo } else { ''$rojo })
                let tag = (if ''$v == 'active' { 'OK  ' } else if ''$v == 'inactive' { 'WARN' } else { 'ERR ' })
                ''$filas = (''$filas | append ''$' (''$col)(''$tag)(''$texto) (''$s | fill -a l -w 18)(''$gris)(''$v)(''$fin)')
              }
            }

            for m in ''$cfg.discos {
              let r = (do -i { ^timeout 1 df -P -k ''$m | complete })
              if ''$r != null and ''$r.exit_code == 0 {
                let f = (''$r.stdout | lines | last | split row --regex '\s+')
                let pct = (do -i { ''$f.4 | str replace '%' ''' | into int } | default (0 - 1))
                if ''$pct >= 0 {
                  let libre = (do -i { (''$f.3 | into int) * 1024 | into filesize } | default 0b)
                  let col = (if ''$pct < 80 { ''$verde } else if ''$pct < 92 { ''$amarillo } else { ''$rojo })
                  let tag = (if ''$pct < 80 { 'OK  ' } else if ''$pct < 92 { 'WARN' } else { 'ERR ' })
                  ''$filas = (''$filas | append ''$' (''$col)(''$tag)(''$texto) (''$m | fill -a l -w 18)(''$gris)(''$pct) % usado, (''$libre) libres(''$fin)')
                }
              }
            }

            if ''$cfg.jobs != ''' {
              let r = (do -i { ^timeout 1 ls -1 ''$cfg.jobs | complete })
              if ''$r != null and ''$r.exit_code == 0 {
                let n = (''$r.stdout | lines | where {|x| ''$x != ''' } | length)
                let et = ('jobs' | fill -a l -w 18)
                ''$filas = (''$filas | append ''$' (''$gris)·    (''$texto)(''$et)(''$gris)(''$n) en (''$cfg.jobs)(''$fin)')
              }
            }

            if not (''$filas | is-empty) { for f in ''$filas { print ''$f } }
          }


          export def sisar-banner [
            --breve        # una sola línea, para las terminales siguientes
          ] {
            let cian = (ansi -e '38;2;41;199;214m')
            let gris = (ansi -e '38;2;92;107;114m')
            let fin = (ansi reset)
            if ''$breve {
              print ''$'(''$cian)SISAR(''$gris) · Sistema Interferometrico SAR · v((sisar-cfg).version)(''$fin)'
              return
            }
            print '''
            sisar-logotipo
            print '''
            sisar-isotipo
            print '''
            sisar-datos
            sisar-paleta
            sisar-estado
            print '''
          }


          # La marca de sesión vive en ''$XDG_RUNTIME_DIR, que systemd borra al cerrar la
          # sesión: así "la primera terminal" vuelve a ser la primera después de cada
          # login, sin dejar basura en el home ni depender de un temporizador.
          export def sisar-bienvenida [] {
            let dir = (''$env.XDG_RUNTIME_DIR? | default (''$env.TMPDIR? | default '/tmp'))
            let marca = ([''$dir 'sisar-banner.lock'] | path join)
            if (''$marca | path exists) {
              sisar-banner --breve
            } else {
              do -i { touch ''$marca }
              sisar-banner
            }
          }
        '';

        # El activador. El usuario sólo agrega `source /etc/nushell/sisar.nu`
        # a su config.nu — una línea, y el resto se actualiza con el sistema.
        "nushell/sisar.nu".text = ''
          # Activa el tema y la bienvenida de SISAR en Nushell.
          # Se carga desde ~/.config/nushell/config.nu con una sola linea:
          #     source /etc/nushell/sisar.nu
          use /etc/nushell/sisar-theme.nu *
          ''$env.config.color_config = (sisar-tema)
          ''$env.config.show_banner = false
          if ''$nu.is-interactive { sisar-bienvenida }
        '';
      }

      # kitty lee /etc/xdg/kitty/kitty.conf cuando el usuario no tiene el suyo.
      (lib.mkIf config.services.desktopManager.plasma6.enable {
        "xdg/kitty/kitty.conf".text = ''
          # Tema SISAR para kitty

          background            #071A22
          foreground            #E3EAEC
          selection_background  #143B4F
          selection_foreground  #F4F7F8
          cursor                #29C7D6
          cursor_text_color     #071A22
          url_color             #29C7D6

          active_tab_background   #29C7D6
          active_tab_foreground   #071A22
          inactive_tab_background #0E3145
          inactive_tab_foreground #C7D0D3
          tab_bar_background      #0E3145

          active_border_color   #29C7D6
          inactive_border_color #0E3145
          bell_border_color     #D8A24A

          color0  #0E2029   # black
          color8  #74858D   # black brillante
          color1  #E2574C   # red
          color9  #F0776C   # red brillante
          color2  #3FB27F   # green
          color10 #63CF9B   # green brillante
          color3  #D8A24A   # yellow
          color11 #F0C069   # yellow brillante
          color4  #4287D0   # blue
          color12 #5A93D8   # blue brillante
          color5  #9A7AD1   # magenta
          color13 #B79AE6   # magenta brillante
          color6  #29C7D6   # cyan
          color14 #7FE3EC   # cyan brillante
          color7  #C7D0D3   # white
          color15 #F4F7F8   # white brillante

          # Tipografía: cambiala por la que tengas instalada.
          # font_family      JetBrains Mono
          # font_size        11.0
        '';
      })
    ];

    # Lo que el banner vigila en ESTE host, más la paleta para scripts que
    # generen salida con color (reportes, figuras, logs del scheduler).
    environment.variables = {
      SISAR_TERM_VERSION = cfg.version;
      SISAR_TERM_SERVICIOS = lib.concatStringsSep " " cfg.servicios;
      SISAR_TERM_DISCOS = lib.concatStringsSep " " cfg.discos;
      SISAR_TERM_JOBS = lib.optionalString (cfg.jobs != null) cfg.jobs;

      SISAR_ABISMO = sisar.abismo;
      SISAR_CIAN = sisar.cian;
      SISAR_ROJO = sisar.rojo;
      SISAR_VERDE = sisar.verde;
      SISAR_AMARILLO = sisar.amarillo;
    };
  };
}
