#
from sidfam import Automaton, AutoGroup
from sidfam.gallery import from_dataset, _from_dataset_topo, print_time
from sidfam.language import any_ip, Variable, no_guard, no_update, \
    no_require, Resource, src_ip, dst_ip
from pathlib import Path
from sys import argv, exit

from time import time
from random import sample, randint

from networkx import shortest_path_length, draw, has_path
from matplotlib import pyplot as plt

FIREWALL_DEGREE_MIN = 30
DIST_TO_FIREWALL_MAX = 7
DIST_TO_EACH_OTHER_MIN = 0
SELECT_RATE = 0.1

print_time('program start: ')

topo, bandwidth_resource, packet_class_list, bandwidth_require = \
    from_dataset(Path(argv[1]))
print(f'actual packet class count: {len(packet_class_list)}')
topo_graph, _c, _r = _from_dataset_topo(Path(argv[1]))
draw(topo_graph, with_labels=True)
plt.savefig('topo.png')

topo_nodes = topo_graph.nodes()
firewalls = sample([n for n in topo_nodes if topo_graph.degree(n) >= FIREWALL_DEGREE_MIN], 2)
print(f'chosen firewalls: {firewalls}')
centers = [
    n for n in topo_nodes
    if has_path(topo_graph, n, firewalls[0]) and
        (shortest_path_length(topo_graph, n, firewalls[0]) < 3 or
        shortest_path_length(topo_graph, n, firewalls[1]) < 3)
]

orphan = Variable()
susp_client = Variable()
blacklist = Variable()
bandwidth = Resource(shared=True)
guard_list = [
    no_guard,
    susp_client < 1000,
    susp_client == 1000,
    orphan == 1,
    orphan == 0
]
require_list = [no_require]
update_list = [
    no_update,
    (orphan << 1) & (susp_client << susp_client + 1) & (blacklist << 1),
    (orphan << 1) & (susp_client << susp_client + 1),
    (orphan << 0) & (susp_client << susp_client - 1)
]

def simple_routing(bw_req):
    req = len(require_list)
    require_list.append(bandwidth * bw_req)
    auto = Automaton()
    auto._append_transition(0, 1, 0, 0, 0, 0)
    auto._append_transition(1, 1, 0, req, 0, 0)
    auto._append_transition(1, 2, 0, 0, 0, -1)
    return auto


def ff_gu(firewall_a, firewall_b, bw_req, g, u):
    req = len(require_list)
    require_list.append(bandwidth * bw_req)
    auto = Automaton()

    # 1: reach A, 2: reach B, 3: neither
    auto._append_transition(0, 1, 0, 0, 0, firewall_a)
    auto._append_transition(0, 2, 0, 0, 0, firewall_b)
    auto._append_transition(0, 3, 0, 0, 0, 0)
    auto._append_transition(3, 1, 0, req, 0, firewall_a)
    auto._append_transition(3, 2, 0, req, 0, firewall_b)
    # 4: reach A & reach B
    auto._append_transition(1, 4, 0, req, 0, firewall_b)
    auto._append_transition(2, 4, 0, req, 0, firewall_a)
    # 5: reach A & guard update, 6: reach B & guard update
    auto._append_transition(1, 5, g, req, u, 0)
    auto._append_transition(2, 6, g, req, u, 0)
    auto._append_transition(3, 5, g, req, u, firewall_a)
    auto._append_transition(3, 6, g, req, u, firewall_b)
    # 7: guard update
    auto._append_transition(3, 7, g, req, u, 0)
    auto._append_transition(7, 5, 0, req, 0, firewall_a)
    auto._append_transition(7, 6, 0, req, 0, firewall_b)
    # 8: reach A & reach B & guard update
    auto._append_transition(5, 8, 0, req, 0, firewall_b)
    auto._append_transition(6, 8, 0, req, 0, firewall_a)
    auto._append_transition(4, 8, g, req, u, 0)
    auto._append_transition(1, 8, g, req, u, firewall_b)
    auto._append_transition(2, 8, g, req, u, firewall_a)
    # 9: accept
    auto._append_transition(8, 9, 0, 0, 0, -1)
    auto._append_transition(4, 9, g, 0, u, -1)

    for i in range(1, 9):
        auto._append_transition(i, i, 0, req, 0, 0)

    return auto


group = AutoGroup(packet_class_list, guard_list, require_list, update_list)
selected_packet_class = []
ff = shortest_path_length(topo_graph, firewalls[0], firewalls[1])
for packet_class in packet_class_list:
    src_host, dst_host = packet_class._src_ip, packet_class._dst_ip
    src_switch, dst_switch = packet_class.endpoints()
    s0 = shortest_path_length(topo_graph, src_switch, firewalls[0])
    s1 = shortest_path_length(topo_graph, src_switch, firewalls[1])
    d0 = shortest_path_length(topo_graph, dst_switch, firewalls[0])
    d1 = shortest_path_length(topo_graph, dst_switch, firewalls[1])
    sd = shortest_path_length(topo_graph, src_switch, dst_switch)
    # if ((
    #     s0 <= DIST_TO_FIREWALL_MAX and d1 <= DIST_TO_FIREWALL_MAX
    # ) or (
    #     s1 <= DIST_TO_FIREWALL_MAX and d0 <= DIST_TO_FIREWALL_MAX
    # )) and sd > DIST_TO_EACH_OTHER_MIN and (
    #     s0 + ff + d1 < sd + 2 or s1 + ff + d0 < sd + 2
    # ):
    # if src_switch == center or dst_switch == center:
    if (src_switch in centers or dst_switch in centers) and \
            (s0 + ff + d1 < sd + 2 or s1 + ff + d0 < sd + 2):
        selected_packet_class.append(packet_class)

print(f'selected count: {len(selected_packet_class)}')
if len(selected_packet_class) < len(packet_class_list) * SELECT_RATE:
    print('selected packet classes is too few, aborting')
    exit()
selected_packet_class = sample(selected_packet_class, int(len(packet_class_list) * SELECT_RATE))
for i, packet_class in enumerate(packet_class_list):
    src_host, dst_host = packet_class._src_ip, packet_class._dst_ip
    src_switch, dst_switch = packet_class.endpoints()
    # group[(src_ip == src_host) & (dst_ip == dst_host)] += \
    #     simple_routing(bandwidth_require[src_host, dst_host])
    req = bandwidth_require[src_host, dst_host]
    # req = randint(1, 2)
    # req = 0.01

    if packet_class in selected_packet_class:
        if dst_switch in centers:
            group._append_automaton(
                ff_gu(firewalls[0], firewalls[1], req, 1, 1),
                i, src_switch, dst_switch
            )
            group._append_automaton(
                ff_gu(firewalls[0], firewalls[1], req, 2, 2),
                i, src_switch, dst_switch
            )
        elif src_switch in centers:
            group._append_automaton(
                ff_gu(firewalls[0], firewalls[1], req, 3, 3),
                i, src_switch, dst_switch
            )
            group._append_automaton(
                ff_gu(firewalls[0], firewalls[1], req, 4, 0),
                i, src_switch, dst_switch
            )
        else:
            assert False
    else:
        group._append_automaton(
            simple_routing(req), i, src_switch, dst_switch
        )
        # pass

# print_time('finish create automaton group: ')

# problem = group @ topo
problem = group._build_path_graph(topo, adaptive_depth_range=5)

print_time('finish searching path: ')

splited = problem.split()

print_time('finish spliting problem: ')

bandwidth.map = bandwidth_resource
rule = splited.solve()

print_time('problem solved: ')

# print(rule)
