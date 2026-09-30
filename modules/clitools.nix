{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    evil-helix
    _7zz
    file

    # Salud de discos. Va en TODOS los hosts y no en los módulos de disco,
    # porque el momento en que se necesita es justo cuando hay que decidir si un
    # disco está fallado — y eso puede pasar en cualquier máquina, incluidas las
    # que no tienen disco de datos. Uno de los WD8006FFBX llegó DOA
    # (2026-09-30) y en los nodos no había smartctl para confirmarlo.
    #
    #   smartctl -a /dev/sdX          estado y atributos
    #   smartctl -t short /dev/sdX    autotest rápido
    smartmontools
    (yazi.override {
      _7zz = _7zz-rar; # Support for RAR extraction
    })
  ];
}
