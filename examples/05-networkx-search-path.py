#
from sidfam.gallery import _from_dataset_topo, from_dataset
from pathlib import Path
from sys import argv
from networkx import all_simple_paths


graph, _c = _from_dataset_topo(Path(argv[1]))
_topo, _res, packet_class_list, _req = from_dataset(Path(argv[1]))

searched_pair_set = set()
for packet_class in packet_class_list:
    if (packet_class._src_switch, packet_class._dst_switch) \
            in searched_pair_set:
        print('skipping')
    path_list = list(all_simple_paths(
        graph,
        source=packet_class._src_switch, target=packet_class._dst_switch,
        cutoff=int(argv[2]) if len(argv) > 2 else 8
    ))
    searched_pair_set.add((packet_class._src_switch, packet_class._dst_switch))
    print(f'searched {len(path_list)} path(s)')
