#
from sidfam import Automaton, AutoGroup
from sidfam.gallery import from_dataset, _from_dataset_topo, print_time
from sidfam.language import any_ip, Variable, no_guard, no_update, \
    no_require, Resource, src_ip, dst_ip, PacketClass
from pathlib import Path
from sys import argv, exit

from time import time
from random import sample, randint, choice

from networkx import shortest_path_length, draw, has_path
from matplotlib import pyplot as plt

# 一些接下来用到的常量，其中影响求值过程的只有`ADAPTIVE`，影响方式参见论文。
FIREWALL_DEGREE_MIN = 30
DIST_TO_FIREWALL_MAX = 7
DIST_TO_EACH_OTHER_MIN = 0
SELECT_RATE = 0.1
ADAPTIVE = 5
AUTO_COMPLEX = int(argv[3]) if len(argv) > 3 else 1
TOL = 3

# `print_time`会打印两次调用`print_time`之间的时间间隔
print_time('program start: ')

# 从命令行参数（`argv[1]`）中指定的文件路径加载拓扑
# 最初的测试应该使用风筝拓扑而不是`dataset`文件夹下的其他复杂拓扑。
topo, bandwidth_resource, packet_class_list, bandwidth_require = \
    from_dataset(Path(argv[1]))

# 接下来的部分全部是复杂（且用不到）的生成Automaton group的过程，看个热闹就好
# 可以直接跳到`problem = ...`那一行
# 根据实验要求，酌情删除或「捏造」一些数据流
demand_count = int(argv[2]) if len(argv) > 2 and int(argv[2]) > 0 else len(packet_class_list)
extra_packet_class_list = []
if len(packet_class_list) > demand_count:
    packet_class_list = sample(packet_class_list, demand_count)
elif len(packet_class_list) < demand_count:
    for i in range(demand_count - len(packet_class_list)):
        pc = choice(packet_class_list)
        extra_packet_class_list.append(PacketClass(pc._src_ip, pc._dst_ip, pc._src_switch, pc._dst_switch))

print(f'actual packet class count: {len(packet_class_list)}')
topo_graph, _c, _r = _from_dataset_topo(Path(argv[1]))
# 将拓扑绘制为PNG图片，检查与预期是否一致。对于Fattree非常有用。
draw(topo_graph, with_labels=True)
plt.savefig('topo.png')

# 从拓扑中选出两个核心位置上的交换机放置防火墙
topo_nodes = topo_graph.nodes()
firewalls = sample([n for n in topo_nodes if topo_graph.degree(n) >= FIREWALL_DEGREE_MIN], 2)
# firewalls = [1, 2]
print(f'chosen firewalls: {firewalls}')
centers = [
    n for n in topo_nodes
    if has_path(topo_graph, n, firewalls[0]) and
        (shortest_path_length(topo_graph, n, firewalls[0]) < 3 or
        shortest_path_length(topo_graph, n, firewalls[1]) < 3)
]

# 定义SNAP变量，断言和更新操作
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
    # `<<`为赋值操作
    (orphan << 1) & (susp_client << susp_client + 1) & (blacklist << 1),
    (orphan << 1) & (susp_client << susp_client + 1),
    (orphan << 0) & (susp_client << susp_client - 1)
]

# 下面分别定义了一个简单的Automaton和一个复杂的Automaton。两者都不太适合接下来的实验，等开会讨论后@whoiscc把合适的Automaton添加上。
def simple_routing(bw_req):
    req = len(require_list)
    require_list.append(bandwidth * bw_req)
    auto = Automaton()
    auto._append_transition(0, 1, 0, 0, 0, 0)
    auto._append_transition(1, 1, 0, req, 0, 0)
    auto._append_transition(1, 2, 0, 0, 0, -1)
    return auto


def ff_gu_single(firewall_a, firewall_b, bw_req, g, u, auto=None, zero=0):
    req = len(require_list)
    require_list.append(bandwidth * bw_req)
    if auto is None:
        auto = Automaton()

    # 1: reach A, 2: reach B, 3: neither
    if zero == 0:
        auto._append_transition(0, 1, 0, 0, 0, firewall_a)
        auto._append_transition(0, 2, 0, 0, 0, firewall_b)
        auto._append_transition(0, 3, 0, 0, 0, 0)
        auto._append_transition(3, 1, 0, req, 0, firewall_a)
        auto._append_transition(3, 2, 0, req, 0, firewall_b)
    # 4: reach A & reach B
    auto._append_transition(1, zero + 4, 0, req, 0, firewall_b)
    auto._append_transition(2, zero + 4, 0, req, 0, firewall_a)
    # 5: reach A & guard update, 6: reach B & guard update
    auto._append_transition(1, zero + 5, g, req, u, 0)
    auto._append_transition(2, zero + 6, g, req, u, 0)
    auto._append_transition(3, zero + 5, g, req, u, firewall_a)
    auto._append_transition(3, zero + 6, g, req, u, firewall_b)
    # 7: guard update
    auto._append_transition(3, zero + 7, g, req, u, 0)
    auto._append_transition(zero + 7, zero + 5, 0, req, 0, firewall_a)
    auto._append_transition(zero + 7, zero + 6, 0, req, 0, firewall_b)
    # 8: reach A & reach B & guard update
    auto._append_transition(zero + 5, zero + 8, 0, req, 0, firewall_b)
    auto._append_transition(zero + 6, zero + 8, 0, req, 0, firewall_a)
    auto._append_transition(zero + 4, zero + 8, g, req, u, 0)
    auto._append_transition(1, zero + 8, g, req, u, firewall_b)
    auto._append_transition(2, zero + 8, g, req, u, firewall_a)
    # 9: accept
    auto._append_transition(zero + 8, zero + 9, 0, 0, 0, -1)
    auto._append_transition(zero + 4, zero + 9, g, 0, u, -1)

    if zero == 0:
        for i in range(1, 4):
            auto._append_transition(i, i, 0, req, 0, 0)
    for i in range(4, 9):
        auto._append_transition(zero + i, zero + i, 0, req, 0, 0)

    return auto

def ff_gu(firewall_a, firewall_b, bw_req, g, u):
    auto = ff_gu_single(firewall_a, firewall_b, bw_req, g, u)
    for i in range(1, AUTO_COMPLEX):
        auto = ff_gu_single(firewall_a, firewall_b, bw_req, g, u, auto, 6 * i)
    return auto


# 创建Automaton group，根据实验需要创建上面的两种Automaton，并把它们添加到Group当中
group = AutoGroup(packet_class_list, guard_list, require_list, update_list)
selected_packet_class = []
ff = shortest_path_length(topo_graph, firewalls[0], firewalls[1])
for packet_class in packet_class_list + extra_packet_class_list:
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
    
    # 只有被选中的孩子才能拥有复杂的Automaton哦
    if (src_switch in centers or dst_switch in centers) and \
            (s0 + ff + d1 < sd + TOL or s1 + ff + d0 < sd + TOL):
        selected_packet_class.append(packet_class)

print(f'selected count: {len(selected_packet_class)}')
if len(selected_packet_class) < demand_count * SELECT_RATE:
    print('selected packet classes is too few, aborting')
    exit()
selected_packet_class = set(sample(selected_packet_class, int(demand_count * SELECT_RATE)))
for i, packet_class in enumerate(packet_class_list + extra_packet_class_list):
    src_host, dst_host = packet_class._src_ip, packet_class._dst_ip
    src_switch, dst_switch = packet_class.endpoints()
    # group[(src_ip == src_host) & (dst_ip == dst_host)] += \
    #     simple_routing(bandwidth_require[src_host, dst_host])
    if packet_class in packet_class_list:
        req = bandwidth_require[src_host, dst_host]
    else:
        req = 0
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

    if (i + 1) % 1000 == 0:
        print(i + 1)

print_time('finish create automaton group: ')

# 在通过某种途径得到Automaton group和拓扑以后，就可以按照下面的顺序逐渐求解问题了
# 分成好几步没有什么特别的原因，只是因为之前的实验需要测量每一步的时间
# 第一步是根据配置（也就是Automaton group）和拓扑生成问题实例
# 对于比较小的拓扑（比如风筝），不需要指定`adaptive_depth_range`，可以使用被注释掉的这种比较简略的写法
# problem = group @ topo
problem = group._build_path_graph(topo, adaptive_depth_range=ADAPTIVE)

print_time('finish searching path: ')

# 接下来将问题拆分成大量的小问题，从而使其可以并行解决
splited = problem.split()

print_time('finish spliting problem: ')

# 在最终解决问题之前，将带宽资源情况传入模型（换言之，带宽资源可以一直到这个时候再确定下来）
bandwidth.map = bandwidth_resource
# 最后解决问题，其实是一个一个地尝试解决小问题
rule = splited.solve()

print_time('problem solved: ')

# 解决完以后，可以把得到的结果打印出来进行观察。切勿在除了风筝以外的拓扑上执行这行代码
# 换句话说，我其实根本不知道在复杂拓扑上求解的结果到底对不对
# print(rule)
