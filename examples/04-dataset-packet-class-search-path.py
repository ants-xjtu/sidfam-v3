#
from sidfam import Automaton, AutoGroup
from sidfam.gallery import from_dataset
from pathlib import Path
from sys import argv

auto = Automaton()
auto._append_transition(0, 1, 0, 0, 0, 0)
# auto._append_transition(0, 3, 0, 0, 0, -1)
auto._append_transition(1, 1, 0, 1, 0, 0)
auto._append_transition(1, 2, 1, 0, 1, 0)
auto._append_transition(1, 3, 1, 1, 1, -1)
auto._append_transition(2, 2, 0, 1, 0, 0)
auto._append_transition(2, 3, 0, 0, 0, -1)

topo, _bandwidth_resource, packet_class_list, _bandwidth_require = \
    from_dataset(Path(argv[1]))
print(f'actual packet class count: {len(packet_class_list)}')

group = AutoGroup()
for packet_class in packet_class_list:
    group[packet_class] += auto

problem = group @ topo
