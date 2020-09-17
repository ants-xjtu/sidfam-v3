# distutils: language=c++
# cython: language_level = 3
from gurobipy import  Model as GRBModel, GRB
from libcpp.vector cimport vector
from libcpp.utility cimport pair
from libcpp.unordered_map cimport unordered_map
from libcpp.string cimport string
from .auto_group cimport AutoGroup
from .path_graph cimport PathGraph

from .gallery import print_time

from random import sample

CUT_OFF = 10

cdef extern from 'hash.hpp':
    pass

cdef Model create_model(
    vector[vector[int]] &model_path, AutoGroup *group, int switch_count,
    vector[vector[float]] &require_list,
    vector[unordered_map[pair[int, int], float]] &resource_list,
    vector[bint] &shared_resource,
    int packet_class_count
):
    model = GRBModel()
    # model_var = [None for _i in range(model_path.size())]

    cdef vector[unordered_map[  # switch
        pair[int, int],  # packet class & guard
        unordered_map[
            pair[int, int],  # update & next hop
            vector[pair[int, int]],  # path graph & path
        ]
    ]] distinguish
    distinguish.resize(switch_count)

    cdef vector[unordered_map[  # resource
        pair[int, int],  # source & destination
        vector[unordered_map[  # packet class
            pair[int, int],  # path graph & path
            float  # require
        ]]
    ]] require
    require.resize(resource_list.size())

    cdef int i, path_index, j, node_index, previous_node_index, k
    cdef int res_index
    cdef float need
    cdef int current_hop, guard, update, next_hop, req
    cdef int packet_class
    cdef pair[int, int] dist_key, dist_action, dist_var, req_key, req_var
    cdef PathGraph *graph
    cdef vector[int] *path
    cdef int path_length

    cdef int var_count = 0
    cdef vector[vector[string]] model_var
    model_var.resize(model_path.size())
    cdef int v, var_row_length
    cdef string constr_file
    constr_file.append(b'Subject To\n')

    cdef int graph_count = model_path.size()
    cdef vector[vector[int]] cut_model_path
    cut_model_path.resize(graph_count)

    cdef Model c_model
    c_model.problem = b''
    # for graph_path in model_path:
    # print(model_path)
    for i in range(graph_count):
        constr_file.append(b'  ')
        if model_path[i].size() == 0:
            return c_model
        # model_var[i] = [
        #     model.addVar(vtype=GRB.BINARY)
        #     for _i in range(graph_path.size())
        # ]

        var_row_length = model_path[i].size()

        if var_row_length > CUT_OFF:
            for v in sample(range(var_row_length), CUT_OFF):
                cut_model_path[i].push_back(model_path[i][v])
            var_row_length = CUT_OFF
        else:
            cut_model_path[i] = model_path[i]

        model_var[i].resize(var_row_length)
        for v in range(var_row_length):
            model_var[i][v] = ('x' + str(var_count)).encode()
            var_count += 1
            constr_file.append(model_var[i][v])
            constr_file.append(b' + ')
            # print(constr_file)
        constr_file.append(b'z = 1\n')

        # model.addConstr(sum(model_var[i]) == 1)

        packet_class = group.automaton_list.at(i).packet_class
        graph = group.path_graph_list.at(i)
        k = 0
        # for path_index in graph_path:
        for path_index in cut_model_path[i]:
            path = &graph.path_list.at(path_index)
            path_length = path.size()
            for j in range(1, path_length):
                previous_node_index = path.at(j - 1)
                node_index = path.at(j)
                current_hop = graph.node_list.at(previous_node_index).next_hop
                guard = graph.node_list.at(node_index).guard
                update = graph.node_list.at(node_index).update
                next_hop = graph.node_list.at(node_index).next_hop

                dist_key = pair[int, int](packet_class, guard)
                dist_action = pair[int, int](update, next_hop)
                dist_var = pair[int, int](i, k)

                if (distinguish[current_hop].count(dist_key) == 0):
                    distinguish[current_hop][dist_key] = unordered_map[
                        pair[int, int],  # update & next hop
                        vector[pair[int, int]],  # path graph & path
                    ]()
                if distinguish[current_hop][dist_key].count(dist_action) == 0:
                    distinguish[current_hop][dist_key][dist_action] = \
                        vector[pair[int, int]]()
                distinguish[current_hop][dist_key][dist_action].push_back(dist_var)

                req = graph.node_list.at(node_index).require
                req_key = pair[int, int](current_hop, next_hop)
                req_var = dist_var

                res_index = 0
                for need in require_list[req]:
                    if need == 0:
                        continue
                    # print(req_key)
                    assert resource_list[res_index].count(req_key) == 1
                    if require[res_index].count(req_key) == 0:
                        require[res_index][req_key] = vector[unordered_map[  # packet class
                            pair[int, int],  # path graph & path
                            float  # require
                        ]]()
                        require[res_index][req_key].resize(packet_class_count)
                    require[res_index][req_key][packet_class][req_var] = need

                    res_index += 1

            k += 1
        i += 1
    print_time('found a possible problem: ')
    # print(constr_file)

    print('add distinguish constraints...')
    cdef pair[pair[int, int], unordered_map[
        pair[int, int],  # update & next hop
        vector[pair[int, int]],  # path graph & path
    ]] key_dist
    cdef pair[pair[int, int], vector[pair[int, int]]] action_dist
    cdef pair[int, int] var_index

    cdef vector[string] collected_var
    cdef string c_var

    for switch_dist in distinguish:
        for key_dist in switch_dist:
    #         # print(key_dist)
    #         choice_var_list = []
            for action_dist in key_dist.second:
    #             collected_var = []
                collected_var.clear()
    #             # print(action_dist)
                collected_var.push_back(('x' + str(var_count)).encode())
                var_count += 1
                for var_index in action_dist.second:
    #                 collected_var.append(
    #                     model_var[var_index.first][var_index.second])
                    constr_file.append(collected_var.back())
                    constr_file.append(b' - ')
                    constr_file.append(model_var[var_index.first][var_index.second])
                    constr_file.append(b' >= 0\n')
    #             choice_var = model.addVar(vtype=GRB.BINARY)
    #             model.addGenConstrMax(choice_var, collected_var)
    #             choice_var_list.append(choice_var)
            if collected_var.size() > 0:
    #             model.addConstr(sum(choice_var_list) <= 1)
                for c_var in collected_var:
                    constr_file.append(c_var)
                    constr_file.append(b' + ')
                constr_file.append(b'z <= 1\n')

    print('add require constraints...')
    cdef float amount
    cdef unordered_map[  # resource
        pair[int, int],  # source & destination
        vector[unordered_map[  # packet class
            pair[int, int],  # path graph & path
            float  # require
        ]]
    ] res_map
    cdef pair[pair[int, int], vector[unordered_map[  # packet class
        pair[int, int],  # path graph & path
        float  # require
    ]]] req_map
    cdef unordered_map[  # packet class
        pair[int, int],  # path graph & path
        float  # require
    ] packet_class_req
    cdef pair[pair[int, int], float] need_pair
    i = 0
    cdef vector[string] packet_class_reqiure_list
    cdef int int_var_count = 0
    for res_map in require:
        for req_map in res_map:
            amount = resource_list[i][req_map.first]
            if shared_resource[i]:
                # packet_class_reqiure_list = []
                packet_class_reqiure_list.clear()
                for packet_class_req in req_map.second:
    #                 max_req = model.addVar(vtype=GRB.CONTINUOUS)
                    packet_class_reqiure_list.push_back(
                        ('y' + str(int_var_count)).encode())
                    int_var_count += 1
    #                 # print(var_index)
                    for need_pair in packet_class_req:
                        var_index = need_pair.first
                        constr_file.append(bytes(str(need_pair.second).encode()))
                        constr_file.append(b' ')
                        constr_file.append(model_var[var_index.first][var_index.second])
                        constr_file.append(b' - ')
                        constr_file.append(packet_class_reqiure_list.back())
                        constr_file.append(b' <= 0\n')
                        # constr_file.append(b'\n')
    #                     model.addConstr(
    #                         model_var[var_index.first][var_index.second] * \
    #                             need_pair.second <= max_req
    #                     )
    #                 packet_class_reqiure_list.append(max_req)
    #             model.addConstr(sum(packet_class_reqiure_list) <= amount)
                for c_var in packet_class_reqiure_list:
                    constr_file.append(c_var)
                    constr_file.append(b' + ')
                constr_file.append(b' z <= ')
                constr_file.append(bytes(str(amount).encode()))
                constr_file.append(b'\n')
        i += 1

    constr_file.append(b'  z = 0\n')

    # for graph_var in model_var:
    #     if graph_var.size() > 10:
    #         dropped_var_index = sample(range(graph_var.size()), graph_var.size() - 10)
    #         for var_i in dropped_var_index:
    #             constr_file.append(b'  ')
    #             constr_file.append(graph_var[var_i])
    #             constr_file.append(b' = 0\n')

    cdef string decl_section
    decl_section.append(b'Binary\n  z ')
    for i in range(var_count):
        decl_section.append(b'x')
        decl_section.append(bytes(str(i).encode()))
        decl_section.append(b' ')
    decl_section.append(b'\n')

    # decl_section.append(b'Integer\n  ')
    # for i in range(int_var_count):
    #     decl_section.append(b'y')
    #     decl_section.append(bytes(str(i).encode()))
    #     decl_section.append(b' ')
    # decl_section.append(b'\n')

    c_model.problem = constr_file + decl_section
    c_model.path = cut_model_path
    c_model.var = model_var
    return c_model
