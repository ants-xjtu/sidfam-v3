# distutils: language=c++
# cython: language_level = 3
from .automaton cimport Automaton
from .path_graph cimport PathGraph
from libcpp.vector cimport vector
from libcpp.unordered_set cimport unordered_set
from libcpp.unordered_map cimport unordered_map
from libcpp.utility cimport pair

cdef struct GroupedAuto:
    Automaton *automaton
    int packet_class
    int src_switch
    int dst_switch

cdef struct AutoGroup:
    vector[GroupedAuto] *automaton_list
    vector[PathGraph *] *path_graph_list

cdef AutoGroup *create_auto_group() except NULL
cdef release_auto_group(AutoGroup *group)
cdef append_automaton(
    AutoGroup *group, Automaton *automaton,
    int packet_class, int src_switch, int dst_switch
)
cdef int build_path_graph(
    AutoGroup *group, unordered_set[pair[int, int]] *topo, int switch_count
) except -1
cdef collect_path(
    AutoGroup *group,
    vector[vector[int]] &guard_dep, vector[vector[int]] &update_dep,
    int variable_count,
    int max_depth,
    shortest_path_length_map, int adaptive_depth_range
)
cdef unordered_map[vector[int], vector[vector[int]]] *collect_model(
    AutoGroup *group)
