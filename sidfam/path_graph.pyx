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
        if transition.next_hop > 0:  # not dot(0), e(-1) or d(-2)
            beyond_dot[transition.src_state].insert(transition.next_hop)

cdef _build_node_list(
    Automaton *automaton,
    vector[Node] *node_list,
    vector[vector[int]] &state_node_list,
    vector[int] &node_origin,
    vector[unordered_set[int]] &beyond_dot,
    int switch_count
):
    # print('start _build_node_list')
    # print(
    #     f'automaton {<unsigned long long> automaton:x} '
    #     f'has state_count: {automaton.state_count}'
    # )
    state_node_list.resize(automaton.state_count)
    # print('resized state_node_list')

    cdef Node node
    cdef int i, j
    cdef Transition *transition
    cdef transition_list_length = automaton.transition_list.size()
    for i in range(transition_list_length):
        # print(f'transition #{i}')
        transition = &automaton.transition_list.at(i)
        if transition.next_hop != 0:
            node.guard = transition.guard
            node.require = transition.require
            node.update = transition.update
            node.next_hop = transition.next_hop
            node.accepted = transition.next_hop < 0
            # print(f'accepted: {node.accepted}')
            node_list.push_back(node)
            node_origin.push_back(i)
            state_node_list[transition.dst_state].push_back(
                node_list.size() - 1)
        else:
            for j in range(switch_count):
                node.guard = transition.guard
                node.require = transition.require
                node.update = transition.update
                node.accepted = False
                if beyond_dot[transition.src_state].count(j) == 0:
                    node.next_hop = j
                    node_list.push_back(node)
                    node_origin.push_back(i)
                    state_node_list[transition.dst_state].push_back(
                        node_list.size() - 1)
    # print('finished _build_node_list')

cdef extern from 'hash_pair.hpp':
    pass

cdef _build_edge_map(
    Automaton *automaton, vector[vector[int]] *edge_map,
    vector[Node] *node_list, vector[int] &node_origin,
    vector[vector[int]] &state_node_list,
    unordered_set[pair[int, int]] &topo,
    int dst_switch
):
    # print('start _build_edge_map')

    cdef node_list_length = node_list.size()
    edge_map.resize(node_list_length)
    # print(f'resized edge_map to {node_list_length}')

    cdef Node *dst_node
    cdef int i, j
    cdef Transition *origin_transition
    cdef int current_hop, next_hop
    for i in range(1, node_list_length):
        # print(f'iterating node_list#{i}')
        dst_node = &node_list.at(i)
        # print('got dst_node')
        next_hop = dst_node.next_hop
        # print(f'visiting transition_list#{node_origin[i]}')
        origin_transition = &automaton.transition_list.at(node_origin[i])
        # print('before inner loop')
        for j in state_node_list[origin_transition.src_state]:
            current_hop = node_list.at(j).next_hop
            if topo.count(pair[int, int](current_hop, next_hop)) == 1 or \
                    (next_hop == -1 and current_hop == dst_switch) or \
                    next_hop == -2:
                # print(f'adding edge {i} -> {j}')
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
    cdef vector[vector[int]] state_node_list
    cdef vector[int] node_origin

    cdef Node origin_node;
    origin_node.guard = -1
    origin_node.require = -1
    origin_node.update = -1
    origin_node.next_hop = src_switch
    origin_node.accepted = False
    node_list.push_back(origin_node)
    node_origin.push_back(-1)
    state_node_list.push_back(vector[int]())
    state_node_list.at(0).push_back(0)

    _build_node_list(
        automaton, node_list, state_node_list, node_origin, beyond_dot,
        switch_count
    )

    # print('before creating edge_map')
    cdef vector[vector[int]] *edge_map = new vector[vector[int]]()
    # print(f'created edge_map at {<unsigned long long> edge_map:x}')
    if edge_map == NULL:
        raise MemoryError()
    _build_edge_map(
        automaton, edge_map, node_list, node_origin, state_node_list,
        topo, dst_switch
    )
    # print('exist _build_edge_map')

    cdef PathGraph *graph = <PathGraph *> PyMem_Malloc(sizeof(PathGraph))
    if graph == NULL:
        raise MemoryError()
    graph.node_list = node_list
    graph.edge_map = edge_map

    return graph

cdef _print_path_graph(PathGraph *graph):
    cdef int edge_map_length = graph.edge_map.size()
    cdef int i, j
    cdef int dst_node_count
    for i in range(edge_map_length):
        dst_node_count = graph.edge_map.at(i).size()
        if dst_node_count == 0:
            continue
        _print_node(graph, i)
        for j in range(dst_node_count):
            _print_node(graph, graph.edge_map.at(i).at(j), prefix='  ')

cdef _print_node(PathGraph *graph, int index, prefix=''):
    cdef Node *node = &graph.node_list.at(index)
    accepted_tag = '(accepted)' if node.accepted else ''
    print(
        f'{prefix}g: {node.guard} r: {node.require} u: {node.update} '
        f'nh: {node.next_hop} {accepted_tag}'
    )

cdef release_path_graph(PathGraph *graph):
    del graph.node_list
    del graph.edge_map
    PyMem_Free(graph)
