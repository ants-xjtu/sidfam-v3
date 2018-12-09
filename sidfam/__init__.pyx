# distutils: language=c++
# cython: language_level = 3
from libcpp.unordered_set cimport unordered_set
from libcpp.utility cimport pair
from .automaton cimport Automaton as CAutomaton, \
    create_automaton, release_automaton, append_transition
from .path_graph cimport PathGraph as CPathGraph, create_path_graph, \
    _print_path_graph, release_path_graph

__all__ = [
    'Automaton',
    'PathGraph',
    'Topo',
]

cdef class Automaton:
    cdef CAutomaton *c_automaton

    def __cinit__(self):
        # print('start create c_automaton')
        self.c_automaton = create_automaton()

    def __dealloc__(self):
        release_automaton(self.c_automaton)

    def _append_transition(
        self,
        int src_state, int dst_state,
        int guard, int require, int update,
        int next_hop
    ):
        append_transition(
            self.c_automaton,
            src_state, dst_state, guard, require, update, next_hop
        )

cdef class PathGraph:
    cdef CPathGraph *c_path_graph

    def __cinit__(
        self, Automaton automaton, Topo topo,
        int src_switch, int dst_switch
    ):
        self.c_path_graph = create_path_graph(
            automaton.c_automaton, src_switch, dst_switch,
            topo.c_topo[0], topo.c_switch_count
        )

    def __dealloc__(self):
        release_path_graph(self.c_path_graph)

    def _print(self):
        _print_path_graph(self.c_path_graph)

cdef extern from 'hash_pair.hpp':
    pass

cdef class Topo:
    cdef unordered_set[pair[int, int]] *c_topo
    cdef int c_switch_count

    def __cinit__(self):
        self.c_topo = NULL
        self.c_switch_count = 0

    def __init__(self, dst_switch_set_map):
        self.c_topo = new unordered_set[pair[int, int]]()
        if self.c_topo == NULL:
            raise MemoryError()
        for src_switch, dst_switch_set in dst_switch_set_map.items():
            if src_switch >= self.c_switch_count:
                self.c_switch_count = src_switch + 1
            for dst_switch in dst_switch_set:
                if dst_switch >= self.c_switch_count:
                    self.c_switch_count = dst_switch + 1
                self.c_topo.insert(pair[int, int](src_switch, dst_switch))

    def __dealloc__(self):
        if self.c_topo != NULL:
            del self.c_topo
