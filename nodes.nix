# nodes.nix — los hosts del cluster, en un solo lugar.
#
# Antes esta lista estaba repetida en flake.nix (hostNames + lan),
# modules/hosts-lan.nix (lan) y modules/nfs-jobs-p2p.nix (lan). Agregar o sacar
# un nodo obligaba a tocar las tres, y el módulo de storage habría sido una
# cuarta copia: cada nodo de cómputo aporta ahora su propio directorio de jobs
# al espacio de nombres compartido, así que la lista pasó a ser parte del
# contrato de almacenamiento y no sólo del direccionamiento.
#
# `server` es el host que exporta el árbol central (archive/, logs/, results/)
# y corre PostgreSQL y la API. `compute` son los que corren un scheduler y
# exportan su propio jobs/.
#
# Para agregar un nodo de cómputo: una línea en `compute`, y nada más.
{
  server = {
    sisar-server = "192.168.0.241";
  };

  compute = {
    sisar1 = "192.168.0.242";
    sisar2 = "192.168.0.243";
    sisar3 = "192.168.0.244";
    sisar4 = "192.168.0.245";
    # sisar5 = "192.168.0.246";
  };
}
