#
from sidfam import Automaton, AutoGroup
from sidfam.gallery import from_dataset
from sidfam.language import any_ip, Variable, no_guard, no_update, \
    no_require, Resource
from pathlib import Path
from sys import argv

from time import time

now = time()

def print_time():
    global now
    print(time() - now)
    now = time()

auto = Automaton()
auto._append_transition(0, 1, 0, 0, 0, 0)
auto._append_transition(1, 1, 0, 1, 0, 0)
auto._append_transition(1, 2, 1, 1, 1, 0)
auto._append_transition(1, 3, 1, 0, 1, -1)
auto._append_transition(2, 2, 0, 1, 0, 0)
auto._append_transition(2, 3, 0, 0, 0, -1)

'''
auto, (s1, s2, s3, s4) = Automaton.with_states(4)
auto[s1]
    .on(no_guard, no_update, no_require, any_switch).to(s2)
auto[s2]
    .on(no_guard, no_update, bandwidth * 0.01, any_switch).to(s2)
    .on(var_x < 1000, var_x << var_x + 1, bandwidth * 0.01, any_switch).to(s3)
    .on(var_x < 1000, var_x << var_x + 1, no_require, end_switch).to(s4)
auto[s3]
    .on(no_guard, no_update, bandwidth * 0.01, any_switch).to(s3)
    .on(no_guard, no_update, no_require, end_switch).to(s4)
auto[s4].accept()
'''

print_time()

topo, bandwidth_resource, packet_class_list, _bandwidth_require = \
    from_dataset(Path(argv[1]))
print(f'actual packet class count: {len(packet_class_list)}')
# topo.no_adaptive()

var_x = Variable()
bandwidth = Resource(shared=True)
guard_list = [no_guard, var_x < 1000]
require_list = [no_require, bandwidth * 0.01]
update_list = [no_update, var_x << var_x + 1]

group = AutoGroup(packet_class_list, guard_list, require_list, update_list)
group[any_ip] += auto

print_time()

# problem = group @ topo
problem = group._build_path_graph(topo, adaptive_depth_range=5)

print_time()

splited = problem.split()

print_time()

bandwidth.map = bandwidth_resource
splited.solve()

print_time()
