#!/usr/bin/env python3
from os import system
from sys import argv

topo_size = [160]
demands_range = (100, 10000)
complex_range = (1, 50)

# collect_script = './time_sum.py'
collect_script = './graph_node_edge.py'

example_script = '10-count-path-graph.py'

if len(argv) <= 1:
    for x in range(demands_range[0], demands_range[1] + 1, 100):
        for y in topo_size:
            # print(x, y)
            while system(f'PYTHONPATH=. python examples/{example_script} dataset/synth/{y} {x} | {collect_script}') != 0:
                pass

else:
    for x in range(complex_range[0], complex_range[1] + 1):
        while system(f'PYTHONPATH=. python examples/{example_script} {argv[1]} 0 {x} | {collect_script}') != 0:
            pass
