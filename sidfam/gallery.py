from . import Topo


class Kite(Topo):
    X = {'A': 1, 'B': 2, 'C': 3, 'D': 4}

    def __init__(self, connect_BD=True, connect_AC=False):
        map = {
            self.X['A']: {self.X['B'], self.X['D']},
            self.X['B']: {self.X['A'], self.X['C']},
            self.X['C']: {self.X['B'], self.X['D']},
            self.X['D']: {self.X['A'], self.X['C']},
        }
        if connect_BD:
            map[self.X['B']].add(self.X['D'])
            map[self.X['D']].add(self.X['B'])
        if connect_AC:
            map[self.X['A']].add(self.X['C'])
            map[self.X['C']].add(self.X['A'])
        super().__init__(map)


def from_dataset(dateset_path):
    with open(dateset_path / 'topo.txt') as topo_file:
        line_type = None
        topo_map = {}
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
                    int(items[0]) + 1, int(items[1]) + 1, items[2]
                if src_switch not in topo_map:
                    topo_map[src_switch] = set()
                topo_map[src_switch].add(dst_switch)
                # if dst_switch in topo_map:
                #     assert src_switch in topo_map[dst_switch]

    topo = Topo(topo_map)
    return topo, None, None, None
