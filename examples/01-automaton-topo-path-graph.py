#
from sidfam import Automaton, PathGraph
from sidfam.gallery import Kite


# print('program start')

auto = Automaton()
auto._append_transition(0, 1, 0, 0, 0, 0)
auto._append_transition(0, 2, 0, 0, 0, Kite.X['B'])
auto._append_transition(1, 1, 0, 1, 0, 0)
auto._append_transition(1, 2, 0, 1, 0, Kite.X['B'])
auto._append_transition(2, 2, 0, 1, 0, 0)
auto._append_transition(2, 3, 0, 0, 0, -1)

graph = PathGraph(auto, Kite(), Kite.X['A'], Kite.X['C'])
graph._print()
