# Toolkit CUDA para las GTX 650 (Kepler, sm_30) — en TODOS los hosts.
#
# CUDA dejó de compilar para compute capability 3.0 (sm_30) a partir de la
# versión 11.0 — el máximo utilizable en esta placa es CUDA 10.2. nixpkgs
# actual (nixos-26.05, ver flake.nix) ya no empaqueta nada anterior a la
# serie 11.4, así que `pkgs.cuda102.cudatoolkit_10_2` viene de un nixpkgs
# viejo (nixos-20.09) fijado como input aparte sólo para esto — ver el
# overlay `cuda102` en flake.nix.
#
# Importante: esto le da a los nodos `nvcc` y las libs de CUDA 10.2 para
# COMPILAR/correr código propio contra sm_30. La mayoría del software CUDA
# de terceros (PyTorch, etc.) ya dejó de publicar binarios para Kepler hace
# años — para usar la GPU desde algo así hay que compilarlo a mano contra
# este mismo toolkit, apuntando a `-arch=sm_30` explícitamente.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cudatoolkit = pkgs.cuda102.cudatoolkit_10_2;
in
{
  environment.systemPackages = [
    cudatoolkit
  ];

  # Mismas variables que arma el propio nixpkgs para cudatoolkit (ver
  # setup-hook histórico): con esto alcanza `nvcc` sin especificar el path
  # completo, y CUDA_PATH queda disponible para cualquier build system
  # (CMake, Docker build args, etc.) que lo busque.
  environment.variables = {
    CUDA_PATH = "${cudatoolkit}";
  };
}
