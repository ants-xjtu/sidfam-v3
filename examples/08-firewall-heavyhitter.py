#
from sidfam import Automaton, AutoGroup
from sidfam.gallery import from_dataset
from sidfam.language import any_ip, Variable, no_guard, no_update, \
    no_require, Resource, src_ip, dst_ip
from pathlib import Path
from sys import argv

from time import time

now = time()

def print_time():
    global now
    print(time() - now)
    now = time()

print_time()

topo, bandwidth_resource, packet_class_list, bandwidth_require = \
    from_dataset(Path(argv[1]))
print(f'actual packet class count: {len(packet_class_list)}')
# topo.no_adaptive()

hh_map = Variable()
hh_counter = Variable()
bandwidth = Resource(shared=True)
guard_list = [no_guard, hh_map < 1]
require_list = [no_require]
update_list = [no_update, hh_counter << hh_counter + 1, hh_map << 1]

def simple_router(bw_req):
    req = len(require_list)
    require_list.append(bandwidth * bw_req)
    auto = Automaton()
    auto._append_transition(0, 1, 0, 0, 0, 0)
    auto._append_transition(1, 1, 0, req, 0, 0)
    auto._append_transition(1, 2, 0, 0, 0, -1)
    return auto

group = AutoGroup(packet_class_list, guard_list, require_list, update_list)
for i, packet_class in enumerate(packet_class_list):
    src_host, dst_host = packet_class._src_ip, packet_class._dst_ip
    # group[(src_ip == src_host) & (dst_ip == dst_host)] += \
    #     simple_router(bandwidth_require[src_host, dst_host])
    group._append_automaton(
        simple_router(bandwidth_require[src_host, dst_host]),
        i, packet_class.endpoints()[0], packet_class.endpoints()[1]
    )

print_time()

# problem = group @ topo
problem = group._build_path_graph(topo, adaptive_depth_range=5)

print_time()

splited = problem.split()

print_time()

bandwidth.map = bandwidth_resource
splited.solve()

print_time()
