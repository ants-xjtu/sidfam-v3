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

from cython.parallel cimport prange
from libc.stdio cimport printf
from libc.stdlib cimport abort

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
    # print(automaton.transition_list.size())
    cdef GroupedAuto auto
    auto.automaton = automaton
    auto.packet_class = packet_class
    auto.src_switch = src_switch
    auto.dst_switch = dst_switch
    group.automaton_list.push_back(auto)
    # print(group.automaton_list.size())
    # print(group.automaton_list.at(0).automaton.transition_list.size())

cdef extern from "hash.hpp":
    pass

ctypedef pair[pair[int, int], Automaton *] GraphKey

cdef int build_path_graph(
    AutoGroup *group, unordered_set[pair[int, int]] *topo, int switch_count
) except -1:
    # print(group.automaton_list.at(0).automaton.transition_list.size())
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
    cdef vector[GraphKey] graph_key_list
    for auto in group.automaton_list[0]:
        # print(f'inside loop #{i}')
        # i += 1
        automaton = auto.automaton
        # print(automaton.transition_list.size())
        src_switch = auto.src_switch
        dst_switch = auto.dst_switch
        graph_id = GraphKey(pair[int, int](src_switch, dst_switch), automaton)
        if graph_map.count(graph_id) == 1:
            # graph = graph_map[graph_id]
            pass
        else:
            # print(automaton.transition_list.size())
            # graph = create_path_graph(
            #     automaton, src_switch, dst_switch, topo[0], switch_count)
            # graph = NULL
            # graph_map[graph_id] = graph
            graph_map[graph_id] = NULL
            graph_key_list.push_back(graph_id)
        # group.path_graph_list.push_back(graph)
        i += 1

    cdef int nodup_graph_count = graph_key_list.size()
    # print(nodup_graph_count)
    print('start creating path graph')
    for i in prange(nodup_graph_count, nogil=True):
        # printf('create #%d\n', i)
        graph_map[graph_key_list[i]] = create_path_graph(
            graph_key_list[i].second,  # auto
            graph_key_list[i].first.first,  # src_switch
            graph_key_list[i].first.second,  # dst_switch
            topo[0], switch_count)
    # print('exit loop')

    for auto in group.automaton_list[0]:
        automaton = auto.automaton
        # print(automaton.transition_list.size())
        src_switch = auto.src_switch
        dst_switch = auto.dst_switch
        graph_id = GraphKey(pair[int, int](src_switch, dst_switch), automaton)
        group.path_graph_list.push_back(graph_map[graph_id])

    print('build path graph finish')

    cdef int max_graph_node_count = 0, max_graph_edge_count = 0
    for key_graph in graph_map:
        node_count = key_graph.second.node_list.size()
        edge_count = sum([node_edge.size() for node_edge in key_graph.second.edge_map[0]])
        if max_graph_node_count < node_count:
            max_graph_node_count = node_count
        if max_graph_edge_count < edge_count:
            max_graph_edge_count = edge_count

    print(f'max #node: {max_graph_node_count}')
    print(f'max #edge: {max_graph_edge_count}')

    return 0

cdef collect_path(
    AutoGroup *group,
    vector[vector[int]] &guard_dep, vector[vector[int]] &update_dep,
    int variable_count,
    int max_depth,
    shortest_path_length_map, int adaptive_depth_range
):
    assert group.path_graph_list != NULL
    cdef int i
    # cdef int depth
    cdef int src_switch, dst_switch
    cdef int graph_count = group.path_graph_list.size()

    cdef vector[int] depth_list
    depth_list.resize(graph_count)
    for i in range(graph_count):
        src_switch = group.automaton_list.at(i).src_switch
        dst_switch = group.automaton_list.at(i).dst_switch
        # print(f'graph #{i}: {src_switch} -> {dst_switch}')
        if shortest_path_length_map is not None and \
                (src_switch, dst_switch) in shortest_path_length_map:
            depth_list[i] = \
                shortest_path_length_map[src_switch, dst_switch] + \
                adaptive_depth_range
        else:
            depth_list[i] = max_depth

    # for path_graph in group.path_graph_list[0]:
    # for i in range(graph_count):
    for i in prange(graph_count, nogil=True):
        # try:
        #     # print('start searching...')
        #     search_path(
        #         path_graph, depth, guard_dep, update_dep, variable_count)
        # except Exception:
        #     raise Exception(
        #         f'{group.automaton_list.at(i).src_switch} -> '
        #         f'{group.automaton_list.at(i).dst_switch} '
        #         f'max_depth: {depth}'
        #     )

        # printf('start search #%d\n', i)
        if search_path(
            group.path_graph_list.at(i),
            depth_list[i], guard_dep, update_dep, variable_count
        ):
            printf(
                'error: %d -> %d max_depth: %d\n',
                group.automaton_list.at(i).src_switch,
                group.automaton_list.at(i).dst_switch,
                depth_list[i]
            )
            # err = True
            abort()

        # print(
        #     f'PathGraph {<unsigned long long> path_graph:x} searched '
        #     f'{path_graph.path_list.size()} path(s) (max_depth: {depth})'
        # )
    cdef long long path_count = 0
    for i in range(graph_count):
        path_count += group.path_graph_list.at(i)[0].path_list.size()
    print(f'path count: {path_count}')


# cdef int search_path_wrapper(
#     PathGraph *graph, int max_depth,
#     vector[vector[int]] &guard_dep, vector[vector[int]] &update_dep,
#     int variable_count
# ) nogil:
#     return search_path(graph, max_depth, guard_dep, update_dep, variable_count)

cdef unordered_map[vector[int], unordered_map[int, vector[int]]] *collect_model(
    AutoGroup *group
):
    cdef int k, path_graph_count = group.path_graph_list.size()
    cdef vector[unordered_map[vector[int], unordered_map[int, vector[int]]]] path_map_list
    path_map_list.resize(path_graph_count)
    cdef vector[int] path_dep
    cdef vector[int] j
    j.resize(path_graph_count, 0)
    cdef vector[int] i
    i.resize(path_graph_count, 0)
    # for i in range(path_graph_count):
    for k in prange(0, path_graph_count, 10, nogil=True):
        i[k] = k
        while i[k] < k + 10 and i[k] < path_graph_count:
        # printf('start graph %d\n', i)
            # printf('i[k]: %d\n', i[k])
            graph = group.path_graph_list.at(i[k])
        # for graph in group.path_graph_list[0]:
            # assert graph.path_list != NULL
            j[i[k]] = 0
            for path_dep in graph.path_dep[0]:
                if path_map_list[i[k]].count(path_dep) == 0:
                    # path_map_list[i[k]][path_dep] = vector[vector[int]]()
                    # path_map_list[i[k]][path_dep].resize(path_graph_count)
                    path_map_list[i[k]][path_dep] = unordered_map[int, vector[int]]()
                if path_map_list[i[k]][path_dep].count(i[k]) == 0:
                    path_map_list[i[k]][path_dep][i[k]] = vector[int]()
                path_map_list[i[k]][path_dep][i[k]].push_back(j[i[k]])
                j[i[k]] += 1
            # printf('finish graph %d\n', i[k])
            i[k] += 1
    merge_splited_map_list(path_map_list)
    cdef unordered_map[vector[int], unordered_map[int, vector[int]]] *result = \
        new unordered_map[vector[int], unordered_map[int, vector[int]]]()
    result.swap(path_map_list[0])
    return result

cdef merge_splited_map_list(
    vector[unordered_map[vector[int], unordered_map[int, vector[int]]]] &splited_map_list
):
    cdef int map_list_length = splited_map_list.size()
    cdef int i = 1, j
    while i < map_list_length:
        printf('start merging at level %d\n', i)
        for j in prange(0, map_list_length, i * 2 , nogil=True):
            merge_two(splited_map_list, j, j + i, map_list_length)
        i *= 2

cdef void merge_two(
    vector[unordered_map[vector[int], unordered_map[int, vector[int]]]] &splited_map_list,
    int a, int b, int max
) nogil:
    if b >= max:
        return
    if splited_map_list[a].size() < splited_map_list[b].size():
        # printf('exchange1\n')
        merge_two(splited_map_list, b, a, max)
        splited_map_list[a].swap(splited_map_list[b])
        return
    # printf("mering: %d %d\n", a, b)
    cdef int graph_count = splited_map_list.size()
    cdef int i, t
    for dep_path in splited_map_list[b]:
        if splited_map_list[a].count(dep_path.first) == 0:
            splited_map_list[a][dep_path.first] = unordered_map[int, vector[int]]()
            splited_map_list[a][dep_path.first].swap(splited_map_list[b][dep_path.first])
        else:
            t = -1
            if splited_map_list[a][dep_path.first].size() < splited_map_list[b][dep_path.first].size():
                t = a
                a = b
                b = t
            # for i in range(graph_count):
            #     if not splited_map_list[b][dep_path.first].count(i):
            #         continue
            for i_val in splited_map_list[b][dep_path.first]:
                i = i_val.first
                if splited_map_list[a][dep_path.first].count(i):
                    if splited_map_list[a][dep_path.first][i].size() > splited_map_list[b][dep_path.first][i].size():
                        splited_map_list[a][dep_path.first][i].insert(
                            splited_map_list[a][dep_path.first][i].end(),
                            splited_map_list[b][dep_path.first][i].begin(),
                            splited_map_list[b][dep_path.first][i].end(),
                        )
                    else:
                        # printf('exchange2\n')
                        splited_map_list[b][dep_path.first][i].insert(
                            splited_map_list[b][dep_path.first][i].end(),
                            splited_map_list[a][dep_path.first][i].begin(),
                            splited_map_list[a][dep_path.first][i].end(),
                        )
                        splited_map_list[a][dep_path.first][i].swap(
                            splited_map_list[b][dep_path.first][i])
                else:
                    splited_map_list[a][dep_path.first][i] = vector[int]()
                    splited_map_list[a][dep_path.first][i].swap(splited_map_list[b][dep_path.first][i])
                    # splited_map_list[a][dep_path.first][i] = splited_map_list[b][dep_path.first][i]
            if t >= 0:
                splited_map_list[a][dep_path.first].swap(splited_map_list[b][dep_path.first])
                t = a
                a = b
                b = t

cdef unordered_map[vector[int], vector[vector[int]]] *extend_splited(
    unordered_map[vector[int], unordered_map[int, vector[int]]] *saved_splited_map,
    int graph_count
):
    # for dep_path in saved_splited_map[0]:
    #     print(dep_path.first)
    #     print([i for i in range(graph_count) if dep_path.second.count(i) == 1])

    cdef unordered_map[vector[int], vector[vector[int]]] *splited_map = \
        new unordered_map[vector[int], vector[vector[int]]]()
    cdef int k

    cdef vector[vector[int]] keys
    for dep_path in saved_splited_map[0]:
        keys.push_back(dep_path.first)
    # print(keys)
    cdef int dep_count = keys.size()
    cdef vector[vector[vector[int]]] splited_map2
    splited_map2.resize(dep_count)

    cdef vector[bint] need_extend
    need_extend.resize(dep_count, True)
    for k in range(dep_count):
        # print(keys[k])
        not_dep = [d == 0 for d in keys[k]]
        if any(not_dep) and not all(not_dep):
            need_extend[k] = False
    # print(need_extend)

    for k in prange(dep_count, nogil=True):
        splited_map2[k].resize(graph_count)
        if need_extend[k]:
            # splited_map[0][keys[k]] = vector[vector[int]]()
            extend_single_dep(splited_map2, saved_splited_map, keys, k, graph_count)

    # for dep_path in saved_splited_map[0]:
    #     splited_map[0][dep_path.first] = vector[vector[int]]()
    #     splited_map[0][dep_path.first].resize(graph_count)
    #     for j in range(graph_count):
    #         if saved_splited_map[0][dep_path.first].count(j):
    #             splited_map[0][dep_path.first][j] = saved_splited_map[0][dep_path.first][j]
    #     for dep_path2 in saved_splited_map[0]:
    #         if first_should_include_second(dep_path.first, dep_path2.first):
    #             # print(f'extending {dep_path.first} << {dep_path2.first}')
    #             for i in range(graph_count):
    #                 if not dep_path2.second.count(i):
    #                     continue
    #                 # print(f'{i}: {dep_path.second[i].size()}')
    #                 splited_map[0][dep_path.first][i].insert(
    #                     splited_map[0][dep_path.first][i].end(),
    #                     dep_path2.second[i].begin(),
    #                     dep_path2.second[i].end()
    #                 )
    #                 # print(f'{i}: {dep_path.second[i].size()}')

    for k in range(dep_count):
        splited_map[0][keys[k]].swap(splited_map2[k])
        # print(splited_map2[k])
    # for dep_path42 in splited_map[0]:
    #     print(dep_path42.first)
    #     print([i for i in range(graph_count) if dep_path42.second[i].size() > 0])

    return splited_map

cdef void extend_single_dep(
    vector[vector[vector[int]]] &splited_map,
    unordered_map[vector[int], unordered_map[int, vector[int]]] *saved_splited_map,
    vector[vector[int]] &keys,
    int k, int graph_count
) nogil:
    # printf('inside %d\n', k)
    cdef int i, j
    dep = keys[k]

    # splited_map[k].resize(graph_count)
    # printf('%d: init\n', k)
    # for j in range(graph_count):
    #     if saved_splited_map[0][dep].count(j):
    #         # printf('%d: init #%d\n', k, j)
    #         splited_map[k][j] = saved_splited_map[0][dep][j]
    for j_val in saved_splited_map[0][dep]:
        splited_map[k][j_val.first] = j_val.second
    # printf('%d: init done\n', k)
    for dep_path2 in saved_splited_map[0]:
        if first_should_include_second(dep, dep_path2.first):
            # printf('extending\n')
            # for i in range(graph_count):
            #     if not dep_path2.second.count(i):
            #         continue
            for i_val in dep_path2.second:
                i = i_val.first
                # print(f'{i}: {dep_path.second[i].size()}')
                # printf('%d: %lu\n', i, splited_map[0][dep][i].size())
                if splited_map[k][i].size() > dep_path2.second[i].size():
                    splited_map[k][i].insert(
                        splited_map[k][i].end(),
                        dep_path2.second[i].begin(),
                        dep_path2.second[i].end()
                    )
                else:
                    dep_path2.second[i].insert(
                        dep_path2.second[i].end(),
                        splited_map[k][i].begin(),
                        splited_map[k][i].end()
                    )
                    splited_map[k][i].swap(dep_path2.second[i])
                # print(f'{i}: {dep_path.second[i].size()}')

cdef bint first_should_include_second(vector[int] &dep1, vector[int] &dep2) nogil:
    # assert dep1.size() == dep2.size()
    cdef int i, dep_count = dep2.size()
    cdef int all_eq = True
    for i in range(dep_count):
        if dep2[i] != dep1[i]:
            all_eq = False
        if dep2[i] == 0:
            continue
        if dep1[i] == 0 or dep2[i] != dep1[i]:
            return False

    return not all_eq
