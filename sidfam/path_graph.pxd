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

cdef struct PathGraph:
    vector[Node] *node_list
    vector[vector[int]] *edge_map
    vector[vector[int]] *path_list

cdef PathGraph *create_path_graph(
    Automaton *automaton, int src_switch, int dst_switch,
    unordered_set[pair[int, int]] &topo, int switch_count
) except NULL
cdef _print_path_graph(PathGraph *graph)
cdef release_path_graph(PathGraph *graph)
cdef search_path(PathGraph *graph, int max_depth)
