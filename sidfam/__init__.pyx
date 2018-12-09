# distutils: language=c++
# cython: language_level = 3
from .automaton cimport Automaton as CAutomaton, \
    create_automaton, release_automaton, append_transition
from .path_graph cimport PathGraph as CPathGraph, create_path_graph

__all__ = [
    'Automaton',
    'PathGraph',
]

cdef class Automaton:
    cdef CAutomaton *c_automaton

    def __cinit__(self):
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
        
    def to_path_graph(self):
        return PathGraph(self)

cdef class PathGraph:
    cdef CPathGraph *c_path_graph
    
    def __cinit__(self, Automaton automaton):
        # self.c_path_graph = create_path_graph(automaton.c_automaton, 0, 0, 0)
        self.c_path_graph = NULL
        
    def __dealloc__(self):
        pass
