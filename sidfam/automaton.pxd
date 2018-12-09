# distutils: language=c++
# cython: language_level = 3
from libcpp.vector cimport vector

cdef struct Transition:
    int src_state
    int dst_state
    int guard
    int require
    int update
    int next_hop
    
cdef struct Automaton:
    int state_count
    vector[Transition] *transition_list
    
cdef Automaton *create_automaton() except NULL
cdef release_automaton(Automaton *automaton)
cdef append_transition(
    Automaton *automaton, 
    int src_state, int dst_state, 
    int guard, int require, int update, 
    int next_hop
)