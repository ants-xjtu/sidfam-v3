#!/usr/bin/env python3
from pathlib import Path
from sys import argv
from networkx import Graph

root_dir = Path(argv[1])
root_dir.mkdir(parents=True, exist_ok=True)
k = int(argv[2])

g = Graph()
# top -> group
for top_switch in range(k):
    connected_switch_in_group = top_switch // (k // 2)
    for connection in range(k):
        group_start = k + connection * (k // 2)
        g.add_edge(top_switch, group_start + connected_switch_in_group)

# group -> edge
for group_switch in range(k, k + k * (k // 2)):
    group_index = (group_switch - k) // (k // 2)
    edge_start = k + k * (k // 2) + group_index * (k // 2)
    for connection in range(k // 2):
        g.add_edge(group_switch, edge_start + connection)

edge_desc = 'edge\n'
# edge -> host
for edge_switch in range(k + k * (k // 2), k + k * k):
    edge_index = edge_switch - (k + k * (k // 2))
    host_desc = ' '.join([f'p{n}' for n in range(edge_index * (k // 2), (edge_index + 1) * (k // 2))])
    edge_desc += f'{edge_switch} {host_desc}\n'

topo_desc = 'link\n'
for src, dst in g.edges:
    topo_desc += f'{src} {dst} 1000\n{dst} {src} 1000\n'

demands_desc = ''
for src in range(k * (k // 2) * (k // 2)):
    for dst in range(k * (k // 2) * (k // 2)):
        demands_desc += f'p{src} p{dst} 0.001\n'

(root_dir / 'topo.txt').write_text(edge_desc + topo_desc)
(root_dir / 'demands.txt').write_text(demands_desc)
