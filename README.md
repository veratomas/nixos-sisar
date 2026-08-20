# SISAR — configuración NixOS (6 hosts)

## Hosts

| Host        | Rol                              |
|-------------|----------------------------------|
| `sisar-nfs` | Servidor NFS + escritorio Plasma |
| `sisar1`    | Cliente NFS (headless)           |
| `sisar2`    | Cliente NFS (headless)           |
| `sisar3`    | Cliente NFS (headless)           |
| `sisar4`    | Cliente NFS (headless)           |
| `sisar5`    | Cliente NFS (headless)           |

Todos comparten `modules/base.nix` (Rust, Python, PostgreSQL/Docker, SSH,
usuarios, consola, Tailscale). `sisar-nfs` suma `nfs-server.nix`, `plasma6.nix`
y `rustdesk.nix`; los demás, `nfs-client.nix`.

## Escritorio en `sisar-nfs`

`sisar-nfs` es el único host con entorno gráfico, para usarlo como terminal de
trabajo: KDE Plasma 6 sobre SDDM, con sesión Wayland (por defecto) y X11
disponible en el selector del login. Incluye Konsole, Kitty y RustDesk.

Los otros cinco siguen headless: `modules/console.nix` deja X, SDDM, Plasma y
el audio en `lib.mkDefault false`, y `plasma6.nix` — importado sólo desde
`hosts/sisar-nfs/default.nix` — los sobrescribe. El `mkDefault` es lo que evita
el error de definiciones en conflicto sin recurrir a `lib.mkForce`.

**RustDesk y Wayland.** La captura de pantalla bajo Wayland pasa por los
portales XDG y PipeWire, y RustDesk todavía tiene fricciones ahí. Si la sesión
remota se ve en negro o no toma el teclado, elegí **Plasma (X11)** en SDDM: por
eso `services.xserver.enable = true` en `plasma6.nix`.

Para conectarse dentro de la LAN sin pasar por los servidores públicos de
RustDesk, hay que activarlo a mano en la app:
*Configuración → Seguridad → Habilitar acceso directo por IP*, más una
contraseña permanente. `modules/rustdesk.nix` ya abre 21115–21119/TCP y
21116/UDP.

Dos advertencias sobre poner escritorio en el servidor NFS: el cierre de
sesión, un reinicio por actualización de drivers o un cuelgue de la sesión
gráfica dejan sin `/mnt/sisar` a los cinco clientes; y la superficie expuesta
crece bastante. Si el objetivo es sólo tener *una* máquina con GUI, considerá
moverlo a un `sisar1` y dejar el servidor headless.

## Antes de desplegar — 3 cosas que hay que tocar

1. **`modules/hosts-lan.nix`** → poné las IPs reales de la LAN
   (por defecto `192.168.1.10`–`.15`).
2. **`modules/nfs-server.nix`** → `lanCidr` debe coincidir con tu red.
3. **`hosts/<host>/hardware-configuration.nix`** → regenerarlo en cada máquina:

   ```
   sudo nixos-generate-config --show-hardware-config \
     > hosts/<host>/hardware-configuration.nix
   ```

   El que viene incluido es una copia del de `sisar1`; el UUID del disco y los
   módulos del kernel son distintos en cada equipo. Verificá también
   `boot.loader.grub.device` en `hosts/<host>/default.nix`.

## Desplegar

En cada máquina, con el repo clonado:

```
sudo nixos-rebuild switch --flake .#sisar1
```

O desde una sola máquina, por SSH:

```
nixos-rebuild switch --flake .#sisar2 --target-host sisar@sisar2 --use-remote-sudo
```

Después del primer arranque, definir contraseñas: `sudo passwd sisar`, etc.

### Desplegar toda la flota con colmena

No hace falta agregarlo como input del flake; alcanza con tenerlo instalado:

```
nix run nixpkgs#colmena -- apply switch          # toda la flota, en paralelo
nix run nixpkgs#colmena -- apply switch --on @server   # sólo sisar-nfs
nix run nixpkgs#colmena -- apply switch --on @client   # sisar1..sisar5
nix run nixpkgs#colmena -- apply build           # sólo evaluar+compilar, sin activar (chequeo previo)
```

Requiere que `modules/admins.nix` tenga la clave pública real de la máquina
desde la que despliegas en `users.users.root.openssh.authorizedKeys.keys`
(colmena se conecta como `root`, con clave — ver `ssh.nix`).

Recomendado: la primera vez, desplegar `sisar-nfs` solo, verificar que sigue
respondiendo, y recién después `--on @client`.

## NFS

Servidor: NFSv4, raíz virtual en `/srv/sisar` (`fsid=0`).

- `/srv/sisar/datos` → los clientes lo ven en `/mnt/sisar/datos`
- `/srv/sisar/home`  → los clientes lo ven en `/mnt/sisar/home`

Los clientes usan `x-systemd.automount`: el montaje ocurre al primer acceso y
el arranque no se bloquea si `sisar-nfs` todavía no está levantado. Con `soft`
las operaciones fallan en lugar de colgar el proceso indefinidamente.

Los UID/GID están fijados a mano (`sisar`=1000, `tvera`=1001, `bpalazzo`=1002,
grupo compartido `sisar-data`=3000) porque NFS mapea por número: si difieren
entre hosts, los permisos se rompen.

Comprobaciones útiles:

```
# en sisar-nfs
sudo exportfs -v
systemctl status nfs-server

# en un cliente
showmount -e sisar-nfs
ls /mnt/sisar/datos
```

## SSH

Habilitado en los 6 hosts (`modules/ssh.nix`), puerto 22, abierto en el
firewall, con `AllowUsers = sisar tvera bpalazzo`, root sin contraseña
(`prohibit-password`) y `X11Forwarding = false`.

Resolución de nombres: entradas estáticas en `/etc/hosts` más mDNS por Avahi,
así que `ssh sisar3` o `ssh sisar3.local` funcionan sin DNS interno.

Recomendación: pasar a claves y luego poner
`PasswordAuthentication = false` en `modules/ssh.nix`.

## Qué se eliminó respecto de la config original

Todo esto sigue fuera de los cinco clientes; en `sisar-nfs` volvieron Plasma,
Konsole, Kitty, RustDesk, las fuentes y la documentación.

**Aplicaciones con interfaz gráfica**

- `office.nix` → OnlyOffice
- `zen-browser` (también se quitó como input del flake)
- `zed-editor`
- `obsidian`
- `tkinter` de la lista de paquetes de Python
- `xterm`

**Otros**

- `assets/nixos_wallpaper.jpg`

## Qué se mantuvo igual

- **Rust** (`modules/rust.nix`): idéntico, `rust-bin.stable.latest.default`
  con los targets gnu y musl, más `openssl`, `pkg-config`, `gcc`.
- **Python** (`modules/python.nix`): idéntico salvo `tkinter`. `matplotlib`
  sigue estando, con `MPLBACKEND=Agg` para que funcione sin pantalla
  (guarda las figuras a archivo).
- PostgreSQL + Docker, Tailscale, NetworkManager, herramientas TUI
  (`evil-helix`, `yazi`, `nushell`, `oh-my-posh`, `fastfetch`, `typst`,
  `tinymist`), locales y zona horaria.

## Red — "Temporary failure in name resolution"

Los valores de `gateway`, `nameservers` e `iface` en `modules/hosts-lan.nix`
son los que hay que verificar contra la red real: las IPs de los hosts pueden
estar bien y aun así no haber internet si el gateway está mal, porque sin ruta
por defecto tampoco se llega al servidor DNS.

Para separar los síntomas, en el host afectado:

```
ip -br addr                 # ¿tomó la IP?
ip route | grep default     # ¿hay ruta por defecto?
ping -c1 192.168.0.1        # ¿responde el gateway?
ping -c1 8.8.8.8            # ¿sale a internet? (routing)
cat /etc/resolv.conf        # ¿hay nameserver?
ping -c1 google.com         # (DNS)
```

Interpretación:

| Resultado                                  | Causa                                  |
|--------------------------------------------|----------------------------------------|
| No hay ruta por defecto                    | `gateway` mal, o el perfil no se aplicó |
| El gateway no responde al ping             | `gateway` es de otra red                |
| `8.8.8.8` anda pero `google.com` no        | sólo DNS: revisar `nameservers`         |
| `resolv.conf` vacío                        | NetworkManager no aplicó `dns`          |

El gateway y el DNS correctos se sacan de un equipo que ya funcione en esa
misma red: `ip route | grep default` y `cat /etc/resolv.conf`. En la red
`icediac` ambos son **192.168.0.240** (no `.1`).

Ojo con el rango: las IPs estáticas `.241`–`.245` tienen que quedar FUERA del
pool de DHCP del router, o tarde o temprano el DHCP le entrega una de esas
direcciones a otro equipo y se produce un conflicto difícil de diagnosticar.

Estado del perfil, en el host:

```
nmcli con show lan
nmcli device show enp3s0
```

Si `nmcli con show` no lista `lan`, el keyfile no se aplicó; si lo lista pero
el dispositivo no lo usa, revisá que `interface-name` coincida con `ip -br link`.

## Colmena — problemas frecuentes

**`nixpkgs.overlays` / `nixpkgs.config` en módulos.** Colmena pasa
`meta.nixpkgs` a cada nodo como `nixpkgs.pkgs`, y el módulo nixpkgs de NixOS
prohíbe combinarlo con `nixpkgs.overlays` o `nixpkgs.config`. El síntoma es una
assertion del estilo *"Your system configures nixpkgs with an externally
created instance"*, o bien `attribute 'rust-bin' missing` / `attribute
'unstable' missing` si el overlay se descartó en silencio. Por eso ambos
overlays y `allowUnfree` viven en `flake.nix` y no en módulos, y por eso se
eliminó `modules/unstable.nix`.

**Permission denied (publickey,password).** Colmena corre SSH sin interacción:
`PasswordAuthentication` no le sirve. El usuario con el que se conecta
(`deployment.targetUser` en `flake.nix`, hoy `root`) tiene que tener autorizada
la clave — y tienen que ser EL MISMO usuario en los dos lados. El error
aparece, típicamente, cuando la clave está autorizada para un usuario y
`targetUser` apunta a otro.

Fuente única: `deployKeys` en `flake.nix`, que `modules/ssh.nix` autoriza para
root. Probá a mano antes de culpar a colmena:

```
ssh -o BatchMode=yes root@192.168.0.242 true
```

Tiene que salir sin pedir nada. Si falla:

```
ssh -v root@192.168.0.242 true 2>&1 | grep -i "offering\|authentications"
```

**Huevo y gallina.** La clave llega a un host recién cuando ESE host aplica la
configuración. En el bootstrap hay que hacer `sudo nixos-rebuild switch` local
(o por SSH con contraseña) en cada máquina una vez; a partir de ahí colmena
puede empujar sola.

**No corras colmena con `sudo`.** Con sudo, SSH usa `/root/.ssh` de tu equipo
local en vez de tu `~/.ssh`, y no encuentra la clave privada. Colmena escala
privilegios en el destino, no en el origen.

**Archivos nuevos que "no existen".** Nix ignora lo que no esté en el índice de
git. Si agregaste un módulo y falla con *path does not exist*, faltó
`git add modules/<archivo>.nix`.

**`colmena: command not found`.** Colmena es un binario externo, no un módulo
de NixOS: no lo instala la config de los hosts. Opciones, de menos a más
permanente:

```
# 1. Una sola vez, sin instalar nada (ojo con el `--`)
nix run nixpkgs#colmena -- apply switch --on @client

# 2. Entrar al devShell del repo (versión fijada por flake.lock)
nix develop
colmena apply switch --on @client
```

Para dejarlo instalado en tu equipo de trabajo, agregá `colmena` a
`environment.systemPackages` de esa máquina. Si el equipo desde el que
desplegás no es NixOS, `nix run` funciona igual mientras tenga nix con flakes
habilitado (`experimental-features = nix-command flakes` en `nix.conf`).

**`cannot update unlocked flake input 'hive' in pure mode`.** Colmena evalúa
los flakes con `nix eval` y para eso necesita la salida `colmenaHive`, generada
con `colmena.lib.makeHive`. Sin ella cae al evaluador viejo
(`nix-instantiate` + `builtins.getFlake`), que no funciona en modo puro con
Nix 2.21+. El flake ya declara el input `colmena` y expone `colmenaHive`; si
venís de una versión anterior del repo, hace falta:

```
nix flake lock   # para agregar el input nuevo
```

Y usar la colmena del input (la del devShell), no cualquiera del sistema: la
de nixpkgs puede ser 0.4.0, que todavía usa el evaluador viejo. Detalles en
https://github.com/zhaofengli/colmena/issues/259

**Diagnóstico.** Separá evaluación de despliegue: `colmena apply build` compila
sin tocar las máquinas, y `--show-trace` da el error completo.

```
nix run nixpkgs#colmena -- apply build --on sisar1 --show-trace
nix run nixpkgs#colmena -- apply switch --on @client -v
nix run nixpkgs#colmena -- apply switch --on sisar-nfs
```

Si `nixos-rebuild build --flake .#sisar1` funciona y `colmena apply build` no,
el problema está en la capa de colmena (los dos puntos de arriba), no en la
configuración del host.

## Nota sobre `flake.lock`

Se conservó el lock original para no mover las versiones. Como se quitó el
input `zen-browser`, la primera evaluación va a regenerar el nodo obsoleto sola.
Si querés forzarlo: `nix flake lock`.
