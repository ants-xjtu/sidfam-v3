# distutils: language=c++
# cython: language_level = 3
from .path_graph cimport PathGraph
from .automaton cimport Automaton, Transition
from libc.stdlib cimport malloc, free
from libcpp.vector cimport vector
from libcpp.unordered_set cimport unordered_set
from libcpp.utility cimport pair
from libcpp.deque cimport deque

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
    int switch_count,
    deque[int] &accepted_node_list
):
    # print('start _build_node_list')
    # print(
    #     f'automaton {<unsigned long long> automaton:x} '
    #     f'has state_count: {automaton.state_count}'
    # )
    # print(automaton.state_count)
    state_node_list.resize(automaton.state_count)
    # print('resized state_node_list')

    cdef Node node
    cdef int i, j
    # cdef Transition *transition
    # cdef int transition_list_length = automaton.transition_list.size()
    # for i in range(transition_list_length):
    for transition in automaton.transition_list[0]:
        # print(f'transition #{i}')
        # transition = &automaton.transition_list.at(i)
        if transition.src_state == 0:
            continue
        if transition.next_hop != 0:
            node.guard = transition.guard
            node.require = transition.require
            node.update = transition.update
            node.next_hop = transition.next_hop
            node.accepted = transition.next_hop < 0
            node.dist = 20000
            # print(f'accepted: {node.accepted}')
            node_list.push_back(node)
            # node_origin.push_back(i)
            node_origin.push_back(transition.src_state)
            state_node_list[transition.dst_state].push_back(
                node_list.size() - 1)
            if node.accepted:
                node_list.back().dist = 0
                accepted_node_list.push_back(node_list.size() - 1)
        else:
            for j in range(switch_count):
                node.guard = transition.guard
                node.require = transition.require
                node.update = transition.update
                node.accepted = False
                node.dist = 20000
                if beyond_dot[transition.src_state].count(j) == 0:
                    node.next_hop = j
                    node_list.push_back(node)
                    node_origin.push_back(transition.src_state)
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
    int dst_switch,
    deque[int] &node_queue,
):
    # print('start _build_edge_map')

    cdef int node_list_length = node_list.size()
    edge_map.resize(node_list_length)
    # print(f'resized edge_map to {node_list_length}')

    cdef vector[bint] visited_node
    visited_node.resize(node_list_length, False)

    cdef Node *dst_node
    cdef int i, j
    # cdef Transition *origin_transition
    cdef int current_hop, next_hop
    # for i in range(1, node_list_length):
    # print(f'node_list length: {node_list_length}')
    while node_queue.size() != 0:
        # print(node_queue.size())
        i = node_queue.front()
        # print(i)
        node_queue.pop_front()
        # visited_node[i] = True
        if i == 0:
            continue
        # print(node_list.at(i).dist)
        # print(f'iterating node_list#{i}')
        dst_node = &node_list.at(i)
        # print('got dst_node')
        next_hop = dst_node.next_hop
        # print(f'visiting transition_list#{node_origin[i]}')
        # origin_transition = &automaton.transition_list.at(node_origin[i])
        # print('before inner loop')
        for j in state_node_list[node_origin[i]]:
            assert j < edge_map.size()
            assert j < node_list.size()
            assert j < visited_node.size()
            # print(j)
            current_hop = node_list.at(j).next_hop
            if topo.count(pair[int, int](current_hop, next_hop)) == 1 or \
                    (next_hop == -1 and current_hop == dst_switch) or \
                    next_hop == -2:
                # print(f'adding edge {i} -> {j}')
                edge_map.at(j).push_back(i)
                # print(i, j)
                if node_list.at(i).dist + 1 < node_list.at(j).dist:
                    # print(f'adjust {j} to {node_list.at(i).dist + 1}')
                    node_list.at(j).dist = node_list.at(i).dist + 1
                if not visited_node[j]:
                    visited_node[j] = True
                    node_queue.push_back(j)

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

    cdef Node initial_node;
    initial_node.guard = 0
    initial_node.require = 0
    initial_node.update = 0
    initial_node.next_hop = src_switch
    initial_node.accepted = False
    initial_node.dist = 20000
    node_list.push_back(initial_node)
    node_origin.push_back(0)

    cdef deque[int] node_queue

    _build_node_list(
        automaton, node_list, state_node_list, node_origin, beyond_dot,
        switch_count, node_queue
    )

    # print('start searching initial_state')
    cdef int initial_state = -1
    for transition in automaton.transition_list[0]:
        # print('inside loop')
        if transition.src_state != 0:
            continue
        if transition.next_hop == src_switch or \
                (transition.next_hop == 0 and \
                    beyond_dot.at(0).count(src_switch) == 0):
            initial_state = transition.dst_state
            break
    assert initial_state > 0
    # print(f'initial_state: {initial_state}')
    state_node_list.at(initial_state).push_back(0)

    # print('before creating edge_map')
    cdef vector[vector[int]] *edge_map = new vector[vector[int]]()
    # print(f'created edge_map at {<unsigned long long> edge_map:x}')
    if edge_map == NULL:
        raise MemoryError()
    _build_edge_map(
        automaton, edge_map, node_list, node_origin, state_node_list,
        topo, dst_switch, node_queue
    )
    assert node_list.at(0).dist < 20000
    # print('exist _build_edge_map')

    cdef PathGraph *graph = <PathGraph *> malloc(sizeof(PathGraph))
    if graph == NULL:
        raise MemoryError()
    graph.node_list = node_list
    graph.edge_map = edge_map

    graph.path_list = NULL
    graph.switch_count = switch_count
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
    # print(
    #     f'releasing node_list {<unsigned long long> graph.node_list:x} '
    #     f'and edge_map {<unsigned long long> graph.edge_map:x}'
    # )
    del graph.node_list
    # print('released node_list')
    del graph.edge_map
    # print('released edge_map')
    if graph.path_list != NULL:
        del graph.path_list
    # print('freeing graph')
    free(graph)
    # print('finished')

cdef search_path(PathGraph *graph, int max_depth):
    if graph.path_list != NULL:
        return
    graph.path_list = new vector[vector[int]]()
    if graph.path_list == NULL:
        raise MemoryError()

    # cdef unordered_set[int] visited_node, visited_switch
    cdef vector[bint] visited_node, visited_switch
    visited_node.resize(graph.node_list.size(), False)
    visited_switch.resize(graph.switch_count, False)
    # visited_node.insert(0)
    # visited_switch.insert(graph.node_list.at(0).next_hop)
    visited_node[0] = True
    assert graph.node_list.at(0).next_hop >= 0
    assert graph.node_list.at(0).next_hop < visited_switch.size()
    visited_switch[graph.node_list.at(0).next_hop] = True
    # visited_switch[graph.node_list[0][0].next_hop] = True
    _search_path_impl(graph, 0, visited_node, visited_switch, 0, max_depth)
    # for path in graph.path_list[0]:
    #     print(', '.join([str(node) for node in path]))

    if graph.path_list.size() == 0:
        raise Exception('graph has no available path')

cdef void _search_path_impl(
    PathGraph *graph, int current_node,
    # unordered_set[int] &visited_node, unordered_set[int] &visited_switch,
    vector[bint] &visited_node, vector[bint] &visited_switch,
    int current_depth, int max_depth
):
    # print(f'at node {current_node}, depth {current_depth}')
    if current_depth == max_depth:
        return
    cdef vector[int] new_path
    if graph.node_list.at(current_node).accepted:
    # if graph.node_list[0][current_node].accepted:
        new_path.resize(current_depth + 1)
        new_path[current_depth] = current_node
        graph.path_list.push_back(new_path)
        # graph.path_list.push_back(vector[int]())
        # graph.path_list.back().resize(current_depth + 1)
        # graph.path_list.back()[current_depth] = current_node
        return

    cdef int old_path_list_len = graph.path_list.size()
    cdef int next_switch
    for next_node in graph.edge_map.at(current_node):
    # for next_node in graph.edge_map[0][current_node]:
        next_switch = graph.node_list.at(next_node).next_hop
        # next_switch = graph.node_list[0][next_node].next_hop
        # if visited_node.count(next_node) != 0 or \
        #         visited_switch.count(next_switch) != 0:
        # if visited_node.at(next_node) or \
        #         (next_switch > 0 and visited_switch.at(next_switch)):
        if visited_node[next_node] or \
                (next_switch > 0 and visited_switch[next_switch]):
            continue

        # IMPORTANT!!!
        if graph.node_list.at(next_node).dist + current_depth > max_depth:
        # if graph.node_list[0][next_node].dist + current_depth > max_depth:
            continue

        # visited_node.insert(next_node)
        # visited_switch.insert(next_switch)
        # assert next_node >= 0 and next_node < visited_node.size()
        # assert next_switch >= 0 and next_switch < visited_switch.size()
        visited_node[next_node] = True
        if next_switch > 0:
            visited_switch[next_switch] = True
        _search_path_impl(
            graph, next_node, visited_node, visited_switch,
            current_depth + 1, max_depth
        )
        # visited_node.erase(next_node)
        # visited_switch.erase(next_switch)
        visited_node[next_node] = False
        if next_switch > 0:
            visited_switch[next_switch] = False
    cdef int i, path_list_len = graph.path_list.size()
    cdef vector[int] *path
    for i in range(old_path_list_len, path_list_len):
        assert i >= 0
        assert i < graph.path_list.size()
        path = &graph.path_list.at(i)
        # path = &graph.path_list[0][i]
        path[0][current_depth] = current_node
        pass
