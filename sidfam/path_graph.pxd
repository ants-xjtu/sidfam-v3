# distutils: language=c++
# cython: language_level = 3
from .automaton cimport Automaton
from libcpp.vector cimport vector
from libcpp.unordered_set cimport unordered_set
from libcpp.utility cimport pair

cdef struct Node:
    int guard
    int require
    int update
    int next_hop
    bint accepted
    int dist

cdef struct PathGraph:
    vector[Node] *node_list
    vector[vector[int]] *edge_map
    vector[vector[int]] *path_list
    vector[vector[int]] *path_dep
    int switch_count

cdef PathGraph *create_path_graph(
    Automaton *automaton, int src_switch, int dst_switch,
    unordered_set[pair[int, int]] &topo, int switch_count
) nogil except NULL
cdef _print_path_graph(PathGraph *graph)
cdef release_path_graph(PathGraph *graph)
cdef int search_path(
    PathGraph *graph, int max_depth,
    vector[vector[int]] &guard_dep, vector[vector[int]] &update_dep,
    int variable_count
) nogil
