extends Control

var _status: Label = null
var _ip_edit: LineEdit = null
var _port_edit: LineEdit = null
var _mp_panel: Control = null
var _busy := false

func _ready() -> void:
        _build_mp_panel()

# 点击空白处（或按任意键）进入单机模式
func _unhandled_input(event):
        if _busy:
                return
        var should_start := false
        if event is InputEventScreenTouch and event.pressed:
                should_start = true
        elif event is InputEventMouseButton and event.pressed:
                should_start = true
        if should_start:
                get_viewport().set_input_as_handled()
                start_game()

func start_game():
        # 防止重复调用
        set_process_unhandled_input(false)
        get_tree().change_scene_to_file('res://scenes/Main.tscn')
        print("游戏开始！")

# ---------- 联机 UI ----------
func _build_mp_panel() -> void:
        _mp_panel = Panel.new()
        _mp_panel.anchor_left = 0.0
        _mp_panel.anchor_top = 1.0
        _mp_panel.anchor_right = 0.42
        _mp_panel.anchor_bottom = 1.0
        _mp_panel.offset_top = -190
        _mp_panel.offset_left = 16
        _mp_panel.offset_bottom = -16
        add_child(_mp_panel)

        var box := VBoxContainer.new()
        box.set_anchors_preset(Control.PRESET_FULL_RECT)
        box.offset_left = 12
        box.offset_top = 8
        box.offset_right = -12
        box.offset_bottom = -8
        box.add_theme_constant_override("separation", 6)
        _mp_panel.add_child(box)

        var title := Label.new()
        title.text = "联机对战（合作）"
        title.add_theme_font_size_override("font_size", 18)
        box.add_child(title)

        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        box.add_child(row)

        _ip_edit = LineEdit.new()
        _ip_edit.placeholder_text = "主机地址 IPv4/IPv6/域名"
        _ip_edit.custom_minimum_size = Vector2(220, 36)
        _ip_edit.text = "127.0.0.1"
        row.add_child(_ip_edit)

        _port_edit = LineEdit.new()
        _port_edit.placeholder_text = "端口"
        _port_edit.text = str(Net.DEFAULT_PORT)
        _port_edit.custom_minimum_size = Vector2(80, 36)
        row.add_child(_port_edit)

        var btn_row := HBoxContainer.new()
        btn_row.add_theme_constant_override("separation", 8)
        box.add_child(btn_row)

        var host_btn := Button.new()
        host_btn.text = "创建主机"
        host_btn.custom_minimum_size = Vector2(130, 40)
        host_btn.pressed.connect(_on_host_pressed)
        btn_row.add_child(host_btn)

        var join_btn := Button.new()
        join_btn.text = "加入游戏"
        join_btn.custom_minimum_size = Vector2(130, 40)
        join_btn.pressed.connect(_on_join_pressed)
        btn_row.add_child(join_btn)

        _status = Label.new()
        _status.text = "主机地址: " + ", ".join(Net.get_local_addresses().slice(0, 3))
        _status.add_theme_font_size_override("font_size", 13)
        _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _status.custom_minimum_size = Vector2(0, 48)
        box.add_child(_status)

func _get_port() -> int:
        var t := _port_edit.text.strip_edges()
        if t.is_valid_int():
                return clampi(int(t), 1024, 65535)
        return Net.DEFAULT_PORT

func _on_host_pressed() -> void:
        if _busy:
                return
        var err := Net.host_game(_get_port())
        if err != OK:
                _status.text = "❌ " + Net.last_error
                return
        _busy = true
        _status.text = "✅ 主机已启动，等待其他玩家加入…"
        # 主机直接进入游戏
        get_tree().change_scene_to_file('res://scenes/Main.tscn')

func _on_join_pressed() -> void:
        if _busy:
                return
        var addr := _ip_edit.text.strip_edges()
        var err := Net.join_game(addr, _get_port())
        if err != OK:
                _status.text = "❌ " + Net.last_error
                return
        _busy = true
        _status.text = "连接中…"
        Net.join_succeeded.connect(func():
                get_tree().change_scene_to_file('res://scenes/Main.tscn'))
        Net.join_failed.connect(func(reason: String):
                _busy = false
                _status.text = "❌ " + reason)
