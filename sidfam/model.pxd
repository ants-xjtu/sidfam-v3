# distutils: language=c++
# cython: language_level = 3
from libcpp.vector cimport vector
from libcpp.unordered_map cimport unordered_map
from libcpp.utility cimport pair
from .auto_group cimport AutoGroup

cdef create_model(
    vector[vector[int]] &model_path, AutoGroup *group, int switch_count,
    vector[vector[float]] &require_list,
    vector[unordered_map[pair[int, int], float]] &resource_list,
    vector[bint] &shared_resource,
    int packet_class_count
)
