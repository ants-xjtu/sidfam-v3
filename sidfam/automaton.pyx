# distutils: language=c++
# cython: language_level = 3
from .automaton cimport Transition, Automaton
from libc.stdlib cimport malloc, free
from libcpp.vector cimport vector

cdef Automaton *create_automaton() except NULL:
    cdef vector[Transition] *transition_list = new vector[Transition]()
    cdef Automaton *automaton = <Automaton *> malloc(sizeof(Automaton))
    if transition_list == NULL or automaton == NULL:
        raise MemoryError()
    automaton.state_count = 2  # 0: initial state, 1: accepted state
    automaton.transition_list = transition_list
    # print(
    #     f'create automaton {<unsigned long long> automaton:x} '
    #     f'with transition_list {<unsigned long long> transition_list:x}'
    # )
    return automaton

cdef release_automaton(Automaton *automaton):
    # print('releasing automaton')
    del automaton.transition_list
    free(automaton)

cdef append_transition(
    Automaton *automaton,
    int src_state, int dst_state,
    int guard, int require, int update,
    int next_hop
):
    # print(
    #     f'append_transition at automaton: '
    #     f'{<unsigned long long> automaton:x}'
    # )
    cdef Transition transition
    transition.src_state = src_state
    transition.dst_state = dst_state
    transition.guard = guard
    transition.require = require
    transition.update = update
    transition.next_hop = next_hop
    automaton.transition_list.push_back(transition)

    if src_state >= automaton.state_count:
        automaton.state_count = src_state + 1
    if dst_state >= automaton.state_count:
        automaton.state_count = dst_state + 1
