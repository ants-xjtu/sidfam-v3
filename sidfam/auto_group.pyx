# distutils: language=c++
# cython: language_level = 3
from .auto_group cimport AutoGroup, GroupedAuto
from .automaton cimport Automaton, release_automaton
from .path_graph cimport PathGraph, create_path_graph, release_path_graph, \
    search_path
from libc.stdlib cimport malloc, free
from libcpp.vector cimport vector
from libcpp.unordered_set cimport unordered_set
from libcpp.unordered_map cimport unordered_map
from libcpp.utility cimport pair

cdef AutoGroup *create_auto_group() except NULL:
    cdef AutoGroup *group = <AutoGroup *> malloc(sizeof(AutoGroup))
    cdef vector[GroupedAuto] *automaton_list = new vector[GroupedAuto]()
    if group == NULL or automaton_list == NULL:
        raise MemoryError()
    group.automaton_list = automaton_list
    group.path_graph_list = NULL
    return group

cdef release_auto_group(AutoGroup *group):
    # cdef unordered_set[Automaton *] automaton_set
    # for auto in group.automaton_list[0]:
    #     automaton_set.insert(auto.automaton)
    # for automaton in automaton_set:
    #     release_automaton(automaton)
    del group.automaton_list

    # print('start cleaning path_graph_list')
    cdef unordered_set[PathGraph *] path_graph_set
    if group.path_graph_list != NULL:
        for path_graph in group.path_graph_list[0]:
            # print(f'inserting PathGraph {<unsigned long long> path_graph:x}')
            path_graph_set.insert(path_graph)
        for path_graph in path_graph_set:
            # print(f'releasing PathGraph {<unsigned long long> path_graph:x}')
            release_path_graph(path_graph)
        del group.path_graph_list
    # print('path_graph_list dropped')
    free(group)
    # print('finished')

cdef append_automaton(
    AutoGroup *group, Automaton *automaton,
    int packet_class, int src_switch, int dst_switch
):
    cdef GroupedAuto auto
    auto.automaton = automaton
    auto.packet_class = packet_class
    auto.src_switch = src_switch
    auto.dst_switch = dst_switch
    group.automaton_list.push_back(auto)

cdef extern from "hash_pair.hpp":
    pass

ctypedef pair[pair[int, int], Automaton *] GraphKey

cdef int build_path_graph(
    AutoGroup *group, unordered_set[pair[int, int]] *topo, int switch_count
) except -1:
    group.path_graph_list = new vector[PathGraph *]()
    if group.path_graph_list == NULL:
        raise MemoryError()
    group.path_graph_list.reserve(group.automaton_list.size())

    cdef unordered_map[GraphKey, PathGraph *] graph_map
    cdef Automaton *automaton
    cdef int src_switch, dst_switch
    cdef PathGraph *graph
    cdef GraphKey graph_id
    # print('before loop')
    cdef int i = 0
    for auto in group.automaton_list[0]:
        # print(f'inside loop #{i}')
        # i += 1
        automaton = auto.automaton
        src_switch = auto.src_switch
        dst_switch = auto.dst_switch
        graph_id = GraphKey(pair[int, int](src_switch, dst_switch), automaton)
        if graph_map.count(graph_id) == 1:
            graph = graph_map[graph_id]
        else:
            graph = create_path_graph(
                automaton, src_switch, dst_switch, topo[0], switch_count)
            # graph = NULL
            graph_map[graph_id] = graph
        group.path_graph_list.push_back(graph)
        print(f'built graph #{i} {<unsigned long long> graph:x}')
        i += 1
    # print('exit loop')
    return 0

cdef collect_path(
    AutoGroup *group,
    vector[vector[int]] &guard_dep, vector[vector[int]] &update_dep,
    int variable_count,
    int max_depth,
    shortest_path_length_map, int adaptive_depth_range
):
    assert group.path_graph_list != NULL
    cdef int i = 0
    cdef int depth
    cdef int src_switch, dst_switch
    for path_graph in group.path_graph_list[0]:
        src_switch = group.automaton_list.at(i).src_switch
        dst_switch = group.automaton_list.at(i).dst_switch
        if shortest_path_length_map is not None and \
                (src_switch, dst_switch) in shortest_path_length_map:
            depth = \
                shortest_path_length_map[src_switch, dst_switch] + \
                adaptive_depth_range
        else:
            depth = max_depth
        try:
            # print('start searching...')
            search_path(
                path_graph, depth, guard_dep, update_dep, variable_count)
        except Exception:
            raise Exception(
                f'{group.automaton_list.at(i).src_switch} -> '
                f'{group.automaton_list.at(i).dst_switch} '
                f'max_depth: {depth}'
            )
        print(
            f'PathGraph {<unsigned long long> path_graph:x} searched '
            f'{path_graph.path_list.size()} path(s) (max_depth: {depth})'
        )
        i += 1
