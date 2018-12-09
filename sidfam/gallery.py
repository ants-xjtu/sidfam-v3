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
