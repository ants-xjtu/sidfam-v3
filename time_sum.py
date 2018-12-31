#!/usr/bin/env python3
from sys import stdin

total_time = 0.0
total_step = 0

for line in stdin:
    if line.startswith('finish building path graph: ') or \
            line.startswith('finish spliting problem: ') or \
            line.startswith('finish searching path: ') or \
            line.startswith('problem solved: '):
        total_time += float(line.split(':')[1])
        total_step += 1

assert total_step == 4
print(total_time)
