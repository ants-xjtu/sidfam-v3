#
from sidfam.gallery import _from_dataset_topo, from_dataset
from pathlib import Path
from sys import argv
from networkx import shortest_path_length


graph, _c = _from_dataset_topo(Path(argv[1]))
_topo, _res, packet_class_list, _req = from_dataset(Path(argv[1]))

path_length_map = {}
for packet_class in packet_class_list:
    if (packet_class._src_switch, packet_class._dst_switch) \
            in path_length_map:
        continue
        # print('skipping')
    length = shortest_path_length(
        graph,
        source=packet_class._src_switch, target=packet_class._dst_switch,
    )
    path_length_map[packet_class._src_switch, packet_class._dst_switch] = \
        length
    # print(f'shortest_path_length = {length}')

with open(Path(argv[1]) / 'shortest_path_length.txt', 'w') as output_file:
    for (src_switch, dst_switch), length in path_length_map.items():
        output_file.write(f'{src_switch} {dst_switch} {length}\n')
