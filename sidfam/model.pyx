# distutils: language=c++
# cython: language_level = 3
# from gurobipy import Model as GRBModel, GRB
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

# 这个函数的输入是……我们所有已经得到的东西，而它的输出是一个字符串形式的优化问题。
# 这种问题的格式类似于：
#   x1 + x2 + x3 <= 0
#   x1 <= 0
#   x2 <= 3
#   y = x1 + x2 - x3
# 把上面这些式子丢给Gurobi，它可以找到一组x1, x2, x3，使y的值最小。
# 我们并没有类似于「某个特征达到最优」这种追求，只需要所有的约束都能满足就已经很好了，所以最后
# 一行通常都是y = 0这样。
# 绝大多数的xi都是0-1变量，不过也有少数不是。对此并没有什么要求，如果有必要的话甚至可以使用
# 连续取值的变量。
# 接下来会详细解释输入的参数都是什么。
# P.S. 全都写完以后发现根本没有解释它们都是什么。没关系，反正用不到。
cdef Model create_model(
    vector[vector[int]] &model_path, AutoGroup *group, int switch_count,
    vector[vector[float]] &require_list,
    vector[unordered_map[pair[int, int], float]] &resource_list,
    vector[bint] &shared_resource,
    int packet_class_count,
    # 额外的信息（比如交换机类别）可以通过这个参数传入，调用的时候用splited.solve(extra=...)即可
    # 可以是任何Python对象。
    extra
):
    # model = GRBModel()
    # model_var = [None for _i in range(model_path.size())]

    # 一般来说添加约束分两步，首先要把约束相关的信息收集整理到一个数据结构中，然后遍历这个结构，
    # 找出所有要添加的约束。下面是两种现有的约束distinguish(dtg)和require(req)所用到的
    # 数据结构，可以看得出来是非常吓人的……

    cdef vector[unordered_map[  # switch
        pair[int, int],  # packet class & guard
        unordered_map[
            pair[int, int],  # update & next hop
            vector[pair[int, int]],  # path graph & path
        ]
    ]] distinguish
    # 对vector调用resize以后，就可以直接访问distinguish[0]至distinguish[switch_count - 1]了
    distinguish.resize(switch_count)

    # dtg约束的意义是，对于拓扑网络中的任何一个交换机，当它看到任何一个数据包的时候，它必须
    # 知道该对这个数据包进行何种操作。如果最后告诉某一台交换机的规则中，既有「从A发往B的包，
    # 你要交给2号」，也有「从A发往B的包，你要交给3号」，就会造成无法确定的结果。
    # 这种约束的核心在于两点。一，在什么情况下，两个数据包对于某台交换机来说是「无法分辨」的？
    # 首先它们必须是从同一个Host出发，到达同一个Host，然后它们不能在当前交换机上进行不同的
    # guard。后一个条件解释起来有点麻烦，只要接受就好。二，如果某台交换机无法分辨某两个数据包，
    # 它可以做什么，不能做什么？事实上，它仍然可以对这两个数据包进行操作，只要进行的操作「完全
    # 一致」，也就是，进行一样的update，并且转发至同一个next hop。
    # 因此，dtg用到的数据结构是一个三层字典的结构。它会把所有的path按照「同一交换机」、「同一
    # 起点/终点以及guard」、「同一update以及next hop」进行分类整理（所以为什么不把三层字典
    # 整合成一层呢？我现在也在深深地思考这个问题……），其中最外层的字典是vector，因为交换机
    # 的名字是从1开始的整数，一般都是连续的。（0被我用来做别的了。）
    # 所以说，path又是什么呢？注释中的path graph又是什么？虽然我拜托你去问李老师了不过还是简单
    # 描述一下。每一条path描述了数据包从进入拓扑网络到流出网络的一种可能的完整路径。其中既包括了
    # 依次经过哪些交换机，还包括了在这些交换机上分别做些什么。因此可以把path看做是长度不确定
    # 的数组，类似于
    #   「我来啦！发往1号交换机」（也就是说，发出Host连接1号交换机）
    #   「在1号交换机上，发往3号」
    #   「在3号交换机上，进行guard1，发往4号」
    #   「在4号交换机上，进行update1，发往终点」
    # 这里的「终点」是指目的Host。因为Host不是交换机，不能直接用在「发往某某」，所以给用一个
    # 特殊的编号（-1）进行指代。
    # 一个path graph包含一组path。在每一个path graph中，我们需要选中一条且只有一条path。
    # 至于为什么是这样又是一个复杂的问题了。如果由于某些原因我们不能做到选中且只选中一条path
    # （也就是说，某个graph中所有的path都不能满足我们的要求），就说明当前的配置没有任何可行
    # 的方案。在Gurobi模型（也就是丢给Gurobi的问题）中，每一条path对应着一个0-1变量。

    # req就不展开讲了，两种约束原理上完全不同，但是步骤完全一样。
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

    # 最外层的for循环对所有的path graph进行遍历
    for i in range(graph_count):
        constr_file.append(b'  ')
        # 如果某一个graph里根本就没有path，那么就不用往下求了肯定无解了。这不是什么严重的问题，
        # 毕竟整个这个函数都这是对一个子问题进行操作，一个不行了还有千千万万个等着。
        if model_path[i].size() == 0:
            return c_model
        # model_var[i] = [
        #     model.addVar(vtype=GRB.BINARY)
        #     for _i in range(graph_path.size())
        # ]

        var_row_length = model_path[i].size()

        # 接下来的一段代码从（同一个graph， 下同的）所有path中随机挑选一些，并且假定这些path
        # 中包含了满足条件的解。考虑到CUT_OFF只有10，这样做看起来风险很大，但是其实能用的
        # path有很多条，所以10条当中也是很有可能有1条符合要求的。
        if var_row_length > CUT_OFF:
            for v in sample(range(var_row_length), CUT_OFF):
                cut_model_path[i].push_back(model_path[i][v])
            var_row_length = CUT_OFF
        else:
            cut_model_path[i] = model_path[i]

        # 所有path对应的0-1变量都存在model_var当中。model_var[i][v]就是第i个graph中的
        # 第v条path所对应的变量。
        # 同时这一段代码还为问题添加了最基本的约束：同一个graph中有且只有1条path被选中。
        # 对constr_file进行的三次append实际上往它末尾添加了一行，形如：
        #   x42 + x43 + ... + x12345 + z = 1
        # 其中所有的xi就是当前正在遍历的第i个graph的所有path对应的变量，最后一个z其实等于0
        # （后面会看到），主要是为了让代码看起来整齐一点……（可以思考一下，还有没有什么好办法
        # 解决「只有最后一个xi的后面没有加号」这个问题，我这个z被李老师吐槽得厉害……）
        model_var[i].resize(var_row_length)
        for v in range(var_row_length):
            model_var[i][v] = ('x' + str(var_count)).encode()
            var_count += 1
            constr_file.append(model_var[i][v])
            constr_file.append(b' + ')
            # print(constr_file)
        constr_file.append(b'z = 1\n')

        # model.addConstr(sum(model_var[i]) == 1)

        # 接下来的几行可以看做是：
        #   foreach 当前graph中的所有path的所有节点:
        #       ....
        # 节点就是上面提到的「我来啦！发往1号」之类的东西。之后写新的约束的时候只要把这一段注释
        # 以下下一段注释以上的代码复制粘贴一下就好了。教人复制粘贴是非常不好的，但是我千算万算
        # 也没想到sidfam居然会以这种方式被拓展……
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

                # ……到此为止。这一段代码之后，我们可以使用这些变量：
                # 目前我们正在遍历的是第i个graph中的第k条路的第j个节点（不要吐槽顺序……）。
                # 在这个节点上，我们正处于current_hop交换机上，在这个交换机上会进行guard
                # 和update（同名变量），然后被发往next_hop交换机。
                # 要注意，j是从1开始数的，也就是说那个「我来啦！」节点不会被遍历到。因为在这个
                # 节点上，没有「当前正处在的交换机」这一说。当遍历到最后一个节点时，next_hop
                # 的值会被设置为-1。

                # 建立后两层字典分别的键（第一层的键就是交换机序号current_hop）和要填入的值。
                dist_key = pair[int, int](packet_class, guard)
                dist_action = pair[int, int](update, next_hop)
                dist_var = pair[int, int](i, k)

                # 如果第二层键不存在……
                if (distinguish[current_hop].count(dist_key) == 0):
                    distinguish[current_hop][dist_key] = unordered_map[
                        pair[int, int],  # update & next hop
                        vector[pair[int, int]],  # path graph & path
                    ]()
                # 如果第三层键不存在……
                if distinguish[current_hop][dist_key].count(dist_action) == 0:
                    distinguish[current_hop][dist_key][dist_action] = \
                        vector[pair[int, int]]()
                # 把值加入字典中合适的位置。
                distinguish[current_hop][dist_key][dist_action].push_back(dist_var)

                # 至此我们要构造的dtg约束就很明显了：在同一个交换机下（第一层键），对于同一个
                # 出发地/目的地和guard（第二层键），最多只能有一种update & next_hop（第三层键）
                # 的path被选中（值为1），也就是对于所有的第三层小字典，最多只能有一个小字典
                # 内部含有1，其它的小字典一个1都不能有。或者干脆大家全都没有1。
                # 这里可以看出，数据结构构建完以后，字典的键基本就没用了，键的作用只是在构造
                # 数据结构的过程中，帮助我们把某个model_var[i][v]扔进合适的小字典里。这一
                # 特性也许有助于思考如何构造数据结构。
                # 以及这样一看，第三层键存在的意义就很清楚了，但是前两层键大概应该是可以合并的。

                # 下面是req约束的数据整理过程。
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

    # 开始构造dtg约束
    print('add distinguish constraints...')
    cdef pair[pair[int, int], unordered_map[
        pair[int, int],  # update & next hop
        vector[pair[int, int]],  # path graph & path
    ]] key_dist
    cdef pair[pair[int, int], vector[pair[int, int]]] action_dist
    cdef pair[int, int] var_index

    cdef vector[string] collected_var
    cdef string c_var

    # 首先遍历每一个交换机
    for switch_dist in distinguish:
        # 这里的写法可以改进，当年我还没有摸清Cython。这两行可以换成
        # for _src_dst_guard, value in switch_dist:
        #     for action_dist in value:
        # 也就是当for ... in ... 的对象是一个C++字典（unordered_map）时，可以直接对它的
        # 键值对进行遍历。
        # 经过这两层for循环我们就进入了某一个二层小字典，现在action_dist是一个字典，这个字典
        # 的键是action也就是update & next_hop，值是要进行这种action的path对应的0-1变量
        # 所组成的列表。整个小字典里所有的path都在路过某个（同一个）交换机时「无法分辨」。
        for key_dist in switch_dist:
    #         # print(key_dist)
    #         choice_var_list = []
            for action_dist in key_dist.second:
    #             collected_var = []
                collected_var.clear()
    #             # print(action_dist)
                # 这里我们创建了新的0-1中间变量collected_var。这些中间变量不直接对应着
                # path，而是用于帮助我们通过更复杂的方式约束path。req约束所用到的0-1变量
                # 就不是0-1类型的。
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
            # 总结一下。假设这个二层小字典里的内容是
            #   {<un1>: [x0, x1, x2], <un2>: [x3, x4], <un3>: [x5, x6, x7, x8]}
            # 其中uni是某种update & next_hop。这段代码会创建3个（每个键对应一个）中间变量
            # x101, x102, x103, 并存放在collected_var中。然后创建如下约束：
            #   x101 - x0 >= 0, x101 - x1 >= 0, x101 - x2 >= 0
            #   x102 - x3 >= 0, x102 - x4 >= 0
            #   x103 - x5 >= 0, x105 - x6 >= 0, x105 - x7 >= 0, x105 - x8 >= 0 （我写这么多干嘛……）
            #   x101 + x102 + x103 + z <= 1
            # 由于x10i都是0-1变量，加起来不超过1就意味着最多有一个是1（也可以都是0），然后
            # 所有的path变量有都不能超过对应的中间变量（x101 - x0 >= 0也就是x101 >= x0），
            # 最终的结果就是三个<uni>当中最多只能有一个，它的值列表中的变量可以是1。
            # 就像这样，最初我们设想中的约束可能比较直觉，但是Gurobi只接受最基本的形式，所以
            # 要通过中间变量和一些技巧把它们进行转化和分解。有一门叫运筹学的课专门有教这个，
            # 非常有趣。

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

    # 出现了，z = 0！
    constr_file.append(b'  z = 0\n')

    # for graph_var in model_var:
    #     if graph_var.size() > 10:
    #         dropped_var_index = sample(range(graph_var.size()), graph_var.size() - 10)
    #         for var_i in dropped_var_index:
    #             constr_file.append(b'  ')
    #             constr_file.append(graph_var[var_i])
    #             constr_file.append(b' = 0\n')

    # 所有用到的变量xi（以及z）要在这里声明。只要遵循和上面代码一样的创建变量的方式就不用管。
    # 看起来现在整个模型中都只有0-1变量了。如果需要用到整数变量可以仿照下面注释掉的代码进行声明。
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

    # 这一篇代码原本是直接调用Gurobi提供的Python接口的Python代码，后来改成了调用Python
    # 接口的Cython代码，后来发现Gurobi的Python接口运行得太慢了，于是又改成生成字符串的Cython
    # 代码……字符串会在__init__.pyx中被一股脑丢给Gurobi，它解析字符串要快得多。只能说机缘巧合
    # 一篇完全可以用Python写的代码最后用了Cython，其中还涉及如此多的数据结构，简直可以说是
    # 最不适合用Cython写的代码了。
    # 综合以上考虑，当你为新的约束构建数据结构的时候，我觉得完全可以直接写Python（所有的Python
    # 代码都是合法的Cython代码），只有在第一次遍历的时候需要复制粘贴一下，剩下的就是append的时候
    # 注意合理encode（C++字符串的append方法只接受bytes类型的参数，所以如果是Python字符串要
    # 先encode才能传进去），基本上可以当做是在写Python。
    # Enjoy coding!
