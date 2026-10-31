extends Node
# 全局联机管理器（Autoload: Net）
# 架构：主机权威（host-authoritative）合作联机。
# 服务器默认双栈监听（ENet bind_ip = "*"），同时接受 IPv4 局域网与 IPv6 远程连接。

enum Mode { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 24565

signal join_succeeded
signal join_failed(reason: String)

var mode: Mode = Mode.OFFLINE
var last_error: String = ""

func is_active() -> bool:
        return mode != Mode.OFFLINE

func is_host() -> bool:
        return mode == Mode.HOST

func is_client() -> bool:
        return mode == Mode.CLIENT

# ---- 创建主机（局域网 IPv4 / IPv6 均可连入）----
func host_game(port: int = DEFAULT_PORT) -> Error:
        var peer := ENetMultiplayerPeer.new()
        # bind_ip 默认为 "*"（通配），双栈监听所有网卡（IPv4 + IPv6）
        var err := peer.create_server(port, 8)
        if err != OK:
                last_error = "端口 %d 无法监听（错误码 %d）" % [port, err]
                return err
        multiplayer.multiplayer_peer = peer
        mode = Mode.HOST
        return OK

# ---- 加入主机 ----
func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
        var parsed := split_address(address, port)
        var host: String = parsed[0]
        var p: int = parsed[1]
        if host.is_empty():
                last_error = "请输入主机地址"
                return ERR_INVALID_PARAMETER
        var peer := ENetMultiplayerPeer.new()
        # ENet 可直接解析 IPv4 / IPv6 字面量与域名
        var err := peer.create_client(host, p)
        if err != OK:
                last_error = "无法发起连接（错误码 %d）" % err
                return err
        multiplayer.multiplayer_peer = peer
        mode = Mode.CLIENT
        # 幂等连接信号（重试加入时避免重复回调）
        if not multiplayer.connected_to_server.is_connected(_on_connected):
                multiplayer.connected_to_server.connect(_on_connected)
        if not multiplayer.connection_failed.is_connected(_on_connect_failed):
                multiplayer.connection_failed.connect(_on_connect_failed)
        return OK

# 解析地址：支持 "host"、"host:port"、"[v6]:port"、纯 IPv6 字面量
static func split_address(address: String, default_port: int) -> Array:
        var addr := address.strip_edges()
        var port := default_port
        if addr.is_empty():
                return [addr, port]
        # [IPv6]:port 形式
        if addr.begins_with("["):
                var close := addr.find("]")
                if close != -1:
                        var host := addr.substr(1, close - 1)
                        var rest := addr.substr(close + 1)
                        if rest.begins_with(":") and rest.substr(1).is_valid_int():
                                port = int(rest.substr(1))
                        return [host, port]
        # host:port（仅一个冒号时才视为带端口；多个冒号视为 IPv6 字面量）
        var colon := addr.rfind(":")
        if colon != -1 and addr.count(":") == 1:
                var p := addr.substr(colon + 1)
                if p.is_valid_int():
                        port = int(p)
                        addr = addr.substr(0, colon)
        return [addr, port]

func _on_connected() -> void:
        join_succeeded.emit()

func _on_connect_failed() -> void:
        last_error = "连接失败：请检查地址/端口，以及主机是否开放了防火墙"
        mode = Mode.OFFLINE
        if multiplayer.multiplayer_peer != null:
                multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
        join_failed.emit(last_error)

# 断开并回到单机状态
func reset() -> void:
        if multiplayer.multiplayer_peer != null:
                multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
        mode = Mode.OFFLINE

# 本机所有 IPv4/IPv6 地址（用于主机界面展示，方便联机时互相同步地址）
func get_local_addresses() -> Array[String]:
        var out: Array[String] = []
        for ip in IP.get_local_addresses():
                var s := str(ip)
                if s.contains("."):
                        # 简单过滤：跳过回环与链路本地
                        if s != "127.0.0.1" and not s.begins_with("169.254"):
                                out.append(s)
                elif s != "::1" and not s.begins_with("fe80"):
                        out.append(s)
        return out
