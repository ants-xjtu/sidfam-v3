# distutils: language=c++
# cython: language_level = 3
from libcpp.unordered_set cimport unordered_set
from libcpp.unordered_map cimport unordered_map
from libcpp.vector cimport vector
from libcpp.utility cimport pair
from .automaton cimport Automaton as CAutomaton, \
    create_automaton, release_automaton, append_transition
from .path_graph cimport PathGraph as CPathGraph, create_path_graph, \
    _print_path_graph, release_path_graph, search_path
from .auto_group cimport AutoGroup as CAutoGroup, create_auto_group, \
    release_auto_group, append_automaton, build_path_graph, collect_path, \
    collect_model, extend_splited
from .model cimport create_model

from .gallery import print_time

from gurobipy import GRB, Model, read

__all__ = [
    'Automaton',
    'PathGraph',
    'Topo',
    'AutoGroup',
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

    # def search_path(self, max_depth=8):
    #     search_path(self.c_path_graph, max_depth)
    #     print(f'{self} searched {self.c_path_graph.path_list.size()} path(s)')

cdef extern from 'hash.hpp':
    pass

cdef class Topo:
    cdef unordered_set[pair[int, int]] *c_topo
    cdef int c_switch_count
    cdef shortest_path_length_map

    def __cinit__(self):
        self.c_topo = NULL
        self.c_switch_count = 0

    def __init__(self, graph, shortest_path_length_map=None):
        self.c_topo = new unordered_set[pair[int, int]]()
        if self.c_topo == NULL:
            raise MemoryError()
        for src_switch, dst_switch in graph.edges:
            if src_switch >= self.c_switch_count:
                self.c_switch_count = src_switch + 1
            if dst_switch >= self.c_switch_count:
                self.c_switch_count = dst_switch + 1
            self.c_topo.insert(pair[int, int](src_switch, dst_switch))
        self.shortest_path_length_map = shortest_path_length_map

    def no_adaptive(self):
        self.shortest_path_length_map = None

    def __dealloc__(self):
        if self.c_topo != NULL:
            del self.c_topo

cdef class AutoGroup:
    cdef CAutoGroup *c_auto_group
    cdef packet_class_list
    cdef vector[vector[int]] c_guard_dep, c_update_dep
    cdef int c_variable_count
    cdef require_list

    cdef automaton_list  # prevent Python Automaton objects to be destoryed

    def __cinit__(self):
        self.c_auto_group = create_auto_group()

    def __init__(
        self, packet_class_list, guard_list, require_list, update_list
    ):
        self.packet_class_list = packet_class_list
        variable_map = {}
        self.c_guard_dep.resize(len(guard_list))
        self.c_update_dep.resize(len(update_list))
        for i, guard in enumerate(guard_list):
            for dep_var in guard.dep:
                if dep_var not in variable_map:
                    variable_map[dep_var] = len(variable_map)
                self.c_guard_dep[i].push_back(variable_map[dep_var])
        for i, update in enumerate(update_list):
            for dep_var in update.dep:
                if dep_var not in variable_map:
                    variable_map[dep_var] = len(variable_map)
                self.c_update_dep[i].push_back(variable_map[dep_var])
        self.c_variable_count = len(variable_map)
        self.require_list = require_list

        self.automaton_list = []

    def __dealloc__(self):
        release_auto_group(self.c_auto_group)

    def _append_automaton(
        self, Automaton automaton,
        int packet_class, int src_switch, int dst_switch
    ):
        append_automaton(
            self.c_auto_group, automaton.c_automaton,
            packet_class, src_switch, dst_switch
        )
        pc = self.packet_class_list[packet_class]
        # print(pc._src_switch, pc._dst_switch)
        self.automaton_list.append(automaton)

    def __getitem__(self, packet_class_constr):
        class Helper:
            def __iadd__(_self, automaton):
                for i, packet_class in enumerate(self.packet_class_list):
                    if packet_class in packet_class_constr:
                        # print(packet_class._src_ip, packet_class._dst_ip)
                        src_switch, dst_switch = packet_class.endpoints()
                        self._append_automaton(
                            automaton, i, src_switch, dst_switch
                        )
                # print('')

        return Helper()

    def __setitem__(self, _key, _value):
        pass

    def _build_path_graph(
        self, Topo topo, max_depth=14, adaptive_depth_range=5, drop_problem=False
    ):
        build_path_graph(self.c_auto_group, topo.c_topo, topo.c_switch_count)
        print_time('finish building path graph: ')
        # print('after build')
        if not drop_problem:
            return Problem(
                self, max_depth,
                topo.shortest_path_length_map, adaptive_depth_range,
                topo
            )

    def __matmul__(self, topo):
        return self._build_path_graph(topo)


cdef class Problem:
    cdef AutoGroup auto_group
    cdef unordered_map[vector[int], vector[vector[int]]] *c_split_map
    cdef Topo topo

    def __init__(
        self, AutoGroup auto_group, int max_depth,
        shortest_path_length_map, int adaptive_depth_range,
        Topo topo
    ):
        # print('inside Problem __init__')
        self.auto_group = auto_group
        collect_path(
            self.auto_group.c_auto_group,
            self.auto_group.c_guard_dep, self.auto_group.c_update_dep,
            self.auto_group.c_variable_count,
            max_depth,
            shortest_path_length_map, adaptive_depth_range
        )
        self.c_split_map = NULL
        # print('exit')
        self.topo = topo

    def split(self):
        print('split problem')
        cdef unordered_map[vector[int], unordered_map[int, vector[int]]]* raw_split_map
        raw_split_map = collect_model(self.auto_group.c_auto_group)

        print('extending problems')
        self.c_split_map = extend_splited(
            raw_split_map, self.auto_group.c_auto_group.path_graph_list.size())
        del raw_split_map
        print('done')
        return SplitedProblem(self.auto_group, self)

    def __dealloc__(self):
        if self.c_split_map != NULL:
            del self.c_split_map


cdef class SplitedProblem:
    cdef AutoGroup auto_group
    cdef Problem problem

    def __init__(self, AutoGroup auto_group, Problem problem):
        self.auto_group = auto_group
        self.problem = problem
        assert self.problem.c_split_map != NULL

    def solve(self, save=False, extra=None):
        require_list, res_map, shared_res = self._preprocess_req()

        cdef int i = 0
        cdef CAutoGroup *group
        for _k, model_path in self.problem.c_split_map[0]:
            print(f'creating model #{i}')
            group = self.auto_group.c_auto_group
            c_model = create_model(
                model_path, group, self.problem.topo.c_switch_count,
                require_list, res_map, shared_res,
                len(self.auto_group.packet_class_list),
                extra
            )
            if c_model.problem == b'':
                print('skipping impossible model')
                i += 1
                continue
            print('create model file')
            with open('/dev/shm/problem.lp', 'wb') as model_file:
                model_file.write(c_model.problem)
            print('create model')
            model = read('/dev/shm/problem.lp')
            # model.params.threads = 1
            model.params.heuristics = 1
            model.params.method = 3
            print('solve model')
            model.optimize()
            if model.status == GRB.Status.OPTIMAL:
                print(f'model #{i} found solution')
                if save:
                    return Rule(self, model, c_model.var, c_model.path)
                else:
                    return
            i += 1

    def _preprocess_req(self):
        cdef vector[vector[float]] require_list
        cdef vector[unordered_map[pair[int, int], float]] res_map
        cdef vector[bint] shared_res

        res_index_map = {}
        for req in self.auto_group.require_list:
            for res in req.res_map.keys():
                if res not in res_index_map:
                    res_index = res_map.size()
                    res_index_map[res] = res_index
                    assert res.map is not None
                    res_map.push_back(unordered_map[pair[int, int], float]())
                    for (src_switch, dst_switch), amount in res.map.items():
                        res_map.back()[
                            pair[int, int](src_switch, dst_switch)
                        ] = amount
                    shared_res.push_back(res.shared)

        for i, req in enumerate(self.auto_group.require_list):
            require_list.push_back(vector[float]())
            require_list.back().resize(res_map.size(), 0)
            for res, need in req.res_map.items():
                assert res in res_index_map
                require_list.back()[res_index_map[res]] = need

        return require_list, res_map, shared_res


class Rule:
    def __init__(self, SplitedProblem splited, model, var_map, path_map):
        self.packet_class_list = splited.auto_group.packet_class_list
        print('generate rules')
        self.switch_action_map = {}
        for i, graph_var in enumerate(var_map):
            packet_class = splited.auto_group.c_auto_group.automaton_list.at(i).packet_class
            graph = splited.auto_group.c_auto_group.path_graph_list.at(i)
            graph_var_val = [model.getVarByName(v) for v in graph_var]
            assert sum(graph_var_val) == 1
            selected_path_index = graph_var_val.index(1)
            selected_path = graph.path_list.at(selected_path_index)
            for j, node in enumerate(selected_path):
                if j == 0:
                    continue
                pre_node = selected_path[j - 1]
                current_switch = graph.node_list.at(pre_node).next_hop
                real_node = graph.node_list.at(node)
                guard = real_node.guard
                update = real_node.update
                # require = real_node.require
                next_switch = real_node.next_hop

                if current_switch not in self.switch_action_map:
                    self.switch_action_map[current_switch] = {}
                    # self.switch_action_map[current_switch] = []
                assert (packet_class, guard) not in self.switch_action_map[current_switch] or \
                    self.switch_action_map[current_switch][packet_class, guard] == (update, next_switch)
                self.switch_action_map[current_switch][packet_class, guard] = (update, next_switch)
                # self.switch_action_map[current_switch].append(
                #     ((packet_class, guard), (update, next_switch)))

    def __str__(self):
        desc = ''
        for switch, switch_rule in self.switch_action_map.items():
            desc += f'SWITCH {switch}\n'
            for pc_g, u_nh in switch_rule.items():
            # for pc_g, u_nh in switch_rule:
                pc = self.packet_class_list[pc_g[0]]
                desc += f'  PACKET CLASS {pc_g[0]}(FROM {pc._src_ip} TO {pc._dst_ip}) GUARD {pc_g[1]} ->\n'
                desc += f'    UPDATE {u_nh[0]} NEXT HOP {u_nh[1]}\n'
            desc += '\n'
        return desc
