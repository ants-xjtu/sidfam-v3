from . import Topo
from .language import PacketClass
from networkx import DiGraph, shortest_path_length

from time import time


class Kite(Topo):
    X = {'A': 1, 'B': 2, 'C': 3, 'D': 4}

    def __init__(self, connect_BD=True, connect_AC=False):
        graph = DiGraph()
        graph.add_edge(self.X['A'], self.X['B'])
        graph.add_edge(self.X['A'], self.X['D'])
        graph.add_edge(self.X['B'], self.X['A'])
        graph.add_edge(self.X['B'], self.X['C'])
        graph.add_edge(self.X['C'], self.X['B'])
        graph.add_edge(self.X['C'], self.X['D'])
        graph.add_edge(self.X['D'], self.X['A'])
        graph.add_edge(self.X['D'], self.X['C'])
        if connect_BD:
            graph.add_edge(self.X['B'], self.X['D'])
            graph.add_edge(self.X['B'], self.X['B'])
        if connect_AC:
            graph.add_edge(self.X['A'], self.X['C'])
            graph.add_edge(self.X['C'], self.X['A'])
        super().__init__(graph)


def _from_dataset_topo(dateset_path):
    with open(dateset_path / 'topo.txt') as topo_file:
        line_type = None
        topo_map = DiGraph()
        connected_switch = {}
        bandwidth_res = {}
        for line in topo_file:
            if line.startswith('edge'):
                line_type = 'edge'
                continue
            elif line.startswith('link'):
                line_type = 'link'
                continue

            assert line_type is not None
            if line_type == 'link':
                items = line.split()
                src_switch, dst_switch, bandwidth = \
                    int(items[0]) + 1, int(items[1]) + 1, float(items[2])
                topo_map.add_edge(src_switch, dst_switch)
                topo_map.add_edge(dst_switch, src_switch)
                if (src_switch, dst_switch) not in bandwidth_res:
                    bandwidth_res[src_switch, dst_switch] = \
                        bandwidth_res[dst_switch, src_switch] = bandwidth
                else:
                    # print(src_switch, dst_switch)
                    assert bandwidth_res[src_switch, dst_switch] == \
                        bandwidth_res[dst_switch, src_switch] == bandwidth, \
                            f'{src_switch} -> {dst_switch} line: {line}'
            if line_type == 'edge':
                items = line.split()
                switch, host_list = int(items[0]) + 1, items[1:]
                for host in host_list:
                    connected_switch[host] = switch
    # topo = Topo(topo_map)
    return topo_map, connected_switch, bandwidth_res

def from_dataset(dateset_path):
    graph, connected_switch, bandwidth_res = _from_dataset_topo(dateset_path)

    packet_class_list = []
    shortest_path_length_map = {}
    bandwidth_req = {}
    with open(dateset_path / 'demands.txt') as demands_file:
        for line in demands_file:
            items = line.split()
            src_host, dst_host, bandwidth = items[0], items[1], float(items[2])
            src_switch = connected_switch[src_host]
            dst_switch = connected_switch[dst_host]
            if src_switch == dst_switch:
                continue
            packet_class_list.append(
                PacketClass(src_host, dst_host, src_switch, dst_switch))
            shortest_path_length_map[src_switch, dst_switch] = \
                shortest_path_length(
                    graph, source=src_switch, target=dst_switch)
            bandwidth_req[src_host, dst_host] = bandwidth

    topo = Topo(graph, shortest_path_length_map)
    # topo = Topo(graph)
    return topo, bandwidth_res, packet_class_list, bandwidth_req


now = time()

def print_time(prefix=''):
    global now
    print(prefix + str(time() - now))
    now = time()
