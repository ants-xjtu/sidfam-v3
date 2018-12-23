#
from sidfam import Automaton, AutoGroup
from sidfam.gallery import from_dataset
from sidfam.language import any_ip, Variable
from pathlib import Path
from sys import argv

auto = Automaton()
auto._append_transition(0, 1, 0, 0, 0, 0)
auto._append_transition(1, 1, 0, 1, 0, 0)
auto._append_transition(1, 2, 1, 1, 1, 0)
auto._append_transition(1, 3, 1, 1, 1, -1)
auto._append_transition(2, 2, 0, 1, 0, 0)
auto._append_transition(2, 3, 0, 0, 0, -1)

topo, _bandwidth_resource, packet_class_list, _bandwidth_require = \
    from_dataset(Path(argv[1]))
print(f'actual packet class count: {len(packet_class_list)}')

var_x = Variable()
guard_list = [var_x < 1000]
require_list = []
update_list = [var_x << var_x + 1]

group = AutoGroup(packet_class_list, guard_list, require_list, update_list)
group[any_ip] += auto

problem = group @ topo
