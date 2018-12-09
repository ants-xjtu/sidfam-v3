# distutils: language=c++
# cython: language_level = 3
from .path_graph cimport PathGraph
from .automaton cimport Automaton, Transition
from cpython.mem cimport PyMem_Malloc, PyMem_Free
from libcpp.vector cimport vector
from libcpp.unordered_set cimport unordered_set
from libcpp.utility cimport pair

cdef _build_beyond_dot(
    Automaton *automaton, 
    vector[unordered_set[int]] &beyond_dot
):
    beyond_dot.resize(automaton.state_count)
    for transition in automaton.transition_list[0]:
        if transition.next_hop >= 0:  # not dot(-1), e(-2), d(-3)
            beyond_dot[transition.src_state].insert(transition.next_hop)

cdef _build_node_list(
    Automaton *automaton, 
    vector[Node] *node_list, 
    vector[vector[int]] &state_node_list,
    vector[int] &node_origin,
    vector[unordered_set[int]] &beyond_dot,
    int switch_count
):
    state_node_list.resize(automaton.state_count)

    cdef Node node
    cdef int i, j
    cdef Transition *transition
    cdef transition_list_length = automaton.transition_list.size()
    for i in range(transition_list_length):
        transition = &automaton.transition_list.at(i)
        if transition.next_hop != -1:
            node.guard = transition.guard
            node.require = transition.require
            node.update = transition.update
            node.next_hop = transition.next_hop
            node_list.push_back(node)
            node_origin.push_back(i)
            state_node_list[transition.dst_state].push_back(
                node_list.size() - 1)
        else:
            for j in range(switch_count):
                node.guard = transition.guard
                node.require = transition.require
                node.update = transition.update
                if beyond_dot[transition.src_state].count(j) == 0:
                    node.next_hop = j
                    node_list.push_back(node)
                    node_origin.push_back(i)
                    state_node_list[transition.dst_state].push_back(
                        node_list.size() - 1)

cdef extern from 'hash_pair.hpp':
    pass

cdef _build_edge_map(
    Automaton *automaton, vector[vector[int]] *edge_map, 
    vector[Node] *node_list, vector[int] &node_origin,
    vector[vector[int]] &state_node_list, 
    unordered_set[pair[int, int]] &topo
):
    cdef node_list_length = node_list.size()
    edge_map.resize(node_list_length)

    cdef Node *dst_node
    cdef int i, j
    cdef Transition *origin_transition
    cdef int current_hop, next_hop
    for i in range(node_list_length):
        dst_node = &node_list.at(i)
        next_hop = dst_node.next_hop
        origin_transition = &automaton.transition_list.at(node_origin[i])
        for j in state_node_list[origin_transition.src_state]:
            current_hop = node_list.at(j).next_hop
            if topo.count(pair[int, int](current_hop, next_hop)) == 1:
                edge_map.at(j).push_back(i)

cdef PathGraph *create_path_graph(
    Automaton *automaton, int src_switch, int dst_switch, 
    unordered_set[pair[int, int]] &topo, int switch_count
) except NULL:
    cdef vector[unordered_set[int]] beyond_dot
    _build_beyond_dot(automaton, beyond_dot)
    
    cdef vector[Node] *node_list = new vector[Node]()
    if node_list == NULL:
        raise MemoryError()
    cdef Node origin_node;
    origin_node.guard = -1
    origin_node.require = -1
    origin_node.update = -1
    origin_node.next_hop = src_switch
    node_list.push_back(origin_node)
    
    cdef vector[vector[int]] state_node_list
    cdef vector[int] node_origin
    _build_node_list(
        automaton, node_list, state_node_list, node_origin, beyond_dot, 
        switch_count
    )
    
    cdef vector[vector[int]] *edge_map = new vector[vector[int]]()
    if edge_map != NULL:
        raise MemoryError()
    _build_edge_map(
        automaton, edge_map, node_list, node_origin, state_node_list, topo);
        
    cdef PathGraph *graph = <PathGraph *> PyMem_Malloc(sizeof(PathGraph))
    if graph == NULL:
        raise MemoryError()
    graph.node_list = node_list
    graph.edge_map = edge_map

    return graph
