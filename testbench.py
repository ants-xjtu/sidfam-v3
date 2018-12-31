#!/usr/bin/env python3
from os import system

for x in range(100, 10001, 100):
    for y in [10, 20, 40, 80, 160]:
        print(x, y)
        while system(f'PYTHONPATH=. python examples/09-firewall-dns.py dataset/synth/{y} {x} | ./time_sum.py') != 0:
            pass
