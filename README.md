# 如何（尝试）运行并确认环境已经搭建好

```bash
$ # 进入项目目录下以后
$ # 1. 激活项目内的Python环境，注意提示符的变化
$ source env/bin/activate
(env) $ # 2. 对Cython模块进行编译，注意：每次修改.pyx和.pyd代码文件后都要执行这条命令
(env) $ #    才能产生效果！
(env) $ python3 setup.py build_ext --inplace
(env) $ # 3. 任意挑选一个拓扑，以它和某个特定的路由配置作为输入，进行求解
(env) $ PYTONPATH=. python3 examples/09-firewall-dns.py dataset/synth/100
```

如果最后一条命令没有报错运行结束，并且最后一行输出类似于`problem solved: 7.823100805282593`，则说明环境无误，可以开始开发工作。

在每一次运行中，求值器接受一个配置（对于每一条流经网络的数据流，路径上一定要/不要经过哪里？带宽资源如何？需要更新和检查哪些状态量？），和一个拓扑网络描述（交换机之间如何相连？主机分别连接在哪一台交换机上？交换机之间的带宽资源情况（主机与交换机之间没有带宽约束）？哪些主机向着哪些主机发送多大的数据流？）。
在上面这条命令中，`09-firewall-dns.py`包含了一个典型的配置，而`dataset/synth/100`为一个标准化拓扑模型。配置和拓扑可以任意排列组合执行，只需要注意少量约束。

# 项目结构

* `sidfam`求值器模块，项目核心
  * `automaton/auto_group/path_graph.pyx/pyd`CODER三大核心抽象的实现和接口定义。具体参考CODER论文。
  * `model.pyx/pyd`将CODER模型转化为MILP的核心代码。在`create_model`函数中为LP添加了约束（目前有distinguish和require两种约束）。对其进行修改需要了解：
    1. Cython基本语法
    2. lp文件格式
    3. Path graph数据结构，在`path_graph.pyd`中定义
  * `__init__.pyx`和`language.py`以及`gallery.py`力图为上层Python用户提供一个不涉及底层操作又足够灵活的平台。`__init__.pyx`允许用户以简练的语法创建Automaton group，`language.py`则提供了Automaton group中必不可少的组成元素，而`gallery.py`中包含了人类的好朋友——风筝拓扑，以及从拓扑数据集中创建拓扑的帮助函数。
* `dataset`常用拓扑数据集
  * `Berkeley` `MIT` `Purdue` `Stanford`以及`rfXXXX`为SNAP论文中使用的拓扑数据（`rfXXXX`对应论文中的`ASXXXX`）。
  * `synth`为标准化拓扑，子文件夹名字的数字对应拓扑中的交换机数目，主机数目为交换机数目的0.7倍，且交换机之间的连接非常均匀。
  * `fattree`为标准的Fattree拓扑，子文件夹名字的数字为Fattree拓扑的参数N。可以通过使用`scripts/gen_fat_tree.py`生成其他的Fattree。
* `examples`各种使用求值器的示例程序，其中的集大成者为`09-firewall-dns.py`，为CODER论文中使用的配置。
* `scripts`辅助脚本，基本退役。
