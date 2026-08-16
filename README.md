# SISAR — configuración NixOS (6 hosts, sin entorno gráfico)

## Hosts

| Host        | Rol                        |
|-------------|----------------------------|
| `sisar-nfs` | Servidor NFS               |
| `sisar1`    | Cliente NFS                |
| `sisar2`    | Cliente NFS                |
| `sisar3`    | Cliente NFS                |
| `sisar4`    | Cliente NFS                |
| `sisar5`    | Cliente NFS                |

Todos comparten `modules/base.nix` (Rust, Python, PostgreSQL/Docker, SSH,
usuarios, consola, Tailscale). La única diferencia entre roles es
`nfs-server.nix` vs `nfs-client.nix`.

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

**Entorno de escritorio y servidores gráficos**

- `plasma6.nix` completo: Plasma 6, SDDM, PipeWire/PulseAudio (audio)
- `services.xserver`, display manager y desktop manager quedan explícitamente
  en `false` (`modules/console.nix`)

**Aplicaciones con interfaz gráfica**

- `office.nix` → OnlyOffice
- `remote-client.nix` → RustDesk (y su puerto TCP 21118 en el firewall)
- `zen-browser` (también se quitó como input del flake)
- `zed-editor`
- `obsidian`
- `kitty` y `xterm` (emuladores de terminal gráficos; la consola TTY y SSH
  no los necesitan)
- `tkinter` de la lista de paquetes de Python

**Otros**

- Fuentes de escritorio (`corefonts`, `nerd-fonts.jetbrains-mono`,
  `libertinus`) y `assets/nixos_wallpaper.jpg`
- `documentation.doc` / `documentation.nixos`

## Qué se mantuvo igual

- **Rust** (`modules/rust.nix`): idéntico, `rust-bin.stable.latest.default`
  con los targets gnu y musl, más `openssl`, `pkg-config`, `gcc`.
- **Python** (`modules/python.nix`): idéntico salvo `tkinter`. `matplotlib`
  sigue estando, con `MPLBACKEND=Agg` para que funcione sin pantalla
  (guarda las figuras a archivo).
- PostgreSQL + Docker, Tailscale, NetworkManager, herramientas TUI
  (`evil-helix`, `yazi`, `nushell`, `oh-my-posh`, `fastfetch`, `typst`,
  `tinymist`), locales y zona horaria.

## Nota sobre `flake.lock`

Se conservó el lock original para no mover las versiones. Como se quitó el
input `zen-browser`, la primera evaluación va a regenerar el nodo obsoleto sola.
Si querés forzarlo: `nix flake lock`.
