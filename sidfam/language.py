#
import operator


class PacketClass:
    def __init__(self, src_ip, dst_ip, src_switch, dst_switch):
        self._src_ip = src_ip
        self._dst_ip = dst_ip
        self._src_switch = src_switch
        self._dst_switch = dst_switch

    def endpoints(self):
        return self._src_switch, self._dst_switch


class IPConstr:
    def __and__(self, other):
        return AndIPConstr(self, other)


class SrcIPConstr:
    def __init__(self, op, rhs):
        self._op = op
        self._rhs = rhs

    def __matmul__(self, packet_class_list):
        for packet_class in packet_class_list:
            if self._op(packet_class._src_ip, self._rhs):
                yield packet_class


class DstIPConstr:
    def __init__(self, op, rhs):
        self._op = op
        self._rhs = rhs

    def __matmul__(self, packet_class_list):
        for packet_class in packet_class_list:
            if self._op(packet_class._dst_ip, self._rhs):
                yield packet_class


class AndIPConstr(IPConstr):
    def __init__(self, constr1, constr2):
        self._constr1 = constr1
        self._constr2 = constr2

    def __matmul(self, packet_class_list):
        return self._constr1 @ (self._constr2 @ packet_class_list)


class SrcIPLHS:
    def __eq__(self, rhs):
        return SrcIPConstr(operator.eq, rhs)

src_ip = SrcIPLHS()


class DstIPLHS:
    def __eq__(self, rhs):
        return DstIPConstr(operator.eq, rhs)

dst_ip = DstIPLHS()
