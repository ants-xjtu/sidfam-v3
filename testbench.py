#!/usr/bin/env python3
from os import system

topo_size = [10, 20, 40, 80, 160]
demands_range = (100, 10000)

for x in range(demands_range[0], demands_range[1] + 1, 100):
    for y in topo_size:
        # print(x, y)
        while system(f'PYTHONPATH=. python examples/09-firewall-dns.py dataset/synth/{y} {x} | ./time_sum.py') != 0:
            pass
