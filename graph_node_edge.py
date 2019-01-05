#!/usr/bin/env python3
from sys import stdin

node_count = -1
edge_count = -1
for line in stdin:
    if line.startswith('max #node: '):
        node_count = int(line.split(': ')[1])
    if line.startswith('max #edge: '):
        edge_count = int(line.split(': ')[1])

assert node_count > 0 and edge_count > 0
print(f'{node_count}, {edge_count}')
