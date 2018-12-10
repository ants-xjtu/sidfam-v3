#
from sidfam import Automaton, PathGraph
from sidfam.gallery import from_dataset
from pathlib import Path
from sys import argv

BYPASS_SWITCH = 3

auto = Automaton()
auto._append_transition(0, 1, 0, 0, 0, 0)
auto._append_transition(0, 2, 0, 0, 0, BYPASS_SWITCH)
auto._append_transition(1, 1, 0, 1, 0, 0)
auto._append_transition(1, 2, 0, 1, 0, BYPASS_SWITCH)
auto._append_transition(2, 2, 0, 1, 0, 0)
auto._append_transition(2, 3, 0, 0, 0, -1)

topo, _bandwidth_resource, _packet_class_list, _bandwidth_require = \
    from_dataset(Path(argv[1]))

graph = PathGraph(auto, topo, 1, 2)
graph._print()
