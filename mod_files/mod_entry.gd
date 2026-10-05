extends Node

# ============================================================
# 同心结 PolyRomance Mod
# 功能：
#   1. 全员同时恋爱（移除嫉妒惩罚）+ 多次举办婚礼
#   2. 圆桌人数上限解除（由 character_manager.gd 覆盖文件提供，恒 99）
#   3. 任务出战人数上限解除（圆桌开放期间临时提升，结算前还原，不影响任务评分）
#   4. The Wolf 与人类 Rufus 共存（拦截治愈剧情中的狼离队信号）
#   5. 圆桌骑士超过 12 人时补齐选择头像 + 底部棋子栏滑轮窗（选中居中滚动）
# 注入方式：覆盖 PankuManager autoload（原功能已完整保留）
# 按 F8 打开/关闭模组菜单
# ============================================================

const MOD_VERSION := "1.3.2"
const CONFIG_PATH := "user://poly_romance.cfg"
const QUEST_MAX_SLOTS := 10

# ---- 原 PankuManager 状态 ----
var panku

# ---- 模组状态 ----
var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _rows_box: VBoxContainer = null
var _lock_toggle: CheckButton = null
var _bypass_marriage_lock: bool = true
var _gideon_really_married: bool = false

var _quest_cap_enabled: bool = true
var _quest_cap_originals := {}

var _wolf_coexist: bool = true
var _demission_filter_installed: bool = false

var _vignette_carousel: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_panku()
	_mod_init()


# ==================== 原 PankuManager 功能（保留） ====================

func _init_panku() -> void:
	var global_class_list := ProjectSettings.get_global_class_list()
	for custom_class in global_class_list:
		if custom_class.get("class") != &"PankuConsole":
			continue
		var console_script = load(custom_class.get("path", ""))
		if console_script == null:
			continue
		var singleton_path = console_script.get_script_constant_map().get("SingletonPath")
		if singleton_path == null:
			var probe = console_script.new()
			singleton_path = probe.get("SingletonPath")
		if singleton_path == null:
			continue
		panku = get_node_or_null(singleton_path)
		if not is_instance_of(panku, console_script):
			panku = null
	if panku:
		_log("Panku manager : console available and initialized")
	else:
		_log("Panku manager : console not available")


func register_shortcut(shortcut: String, object: Object):
	if not panku:
		return
	panku.gd_exprenv.register_env(shortcut, object)


func execute(expr: String) -> Dictionary:
	if not panku:
		return {}
	return panku.gd_exprenv.execute(expr)


func show_panku(is_visible: bool):
	if not panku:
		return
	panku.windows_manager.visible = is_visible


# ==================== 日志 ====================

func _log(msg: String) -> void:
	print(msg)
	var f: FileAccess
	if FileAccess.file_exists("user://poly_romance.log"):
		f = FileAccess.open("user://poly_romance.log", FileAccess.READ_WRITE)
	else:
		f = FileAccess.open("user://poly_romance.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(Time.get_datetime_string_from_system() + " " + msg)
	f.close()


# ==================== 模组初始化 ====================

func _mod_init() -> void:
	_load_config()
	_log("[PolyRomance] 同心结 mod v%s 已加载 (F8 打开菜单)" % MOD_VERSION)
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	_build_ui()
	var seb := get_node_or_null("/root/SignalsEventBus")
	if seb != null:
		_connect_if(seb, "cycle_transition_finished", _apply_polyamory)
		_connect_if(seb, "cycle_transition_finished", _install_demission_filter)
		_connect_if(seb, "character_romance_updated", _on_character_romance_updated)
		_connect_if(seb, "ending_triggered", _on_ending_triggered)
		_connect_if(seb, "roundtable_opened_with_knights", _on_roundtable_opened)
		_connect_if(seb, "roundtable_finished", _on_roundtable_finished)
	var sc := get_node_or_null("/root/StoryController")
	if sc != null and sc.has_signal("story_loaded"):
		sc.connect("story_loaded", _on_story_loaded)
	_reapply_loop()
	_start_slot_tint_loop()


func _connect_if(obj: Object, sig: String, fn: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, fn):
		obj.connect(sig, fn)


# 角色资源在 autoload 之后才加载完毕，前 20 秒反复套用一次
func _reapply_loop() -> void:
	for i in range(10):
		await get_tree().create_timer(2.0).timeout
		_apply_polyamory()
		_install_demission_filter()
		_ensure_knight_vignettes()
		if i == 4:
			_diag("boot")


func _char_manager() -> Node:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.get("character_manager")


func _quests_manager() -> Node:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.get("quests_manager")


# ==================== 功能 1：嫉妒免疫 ====================

func _apply_polyamory() -> void:
	var cm := _char_manager()
	if cm == null:
		return
	var fixed := 0
	for arr_name in ["roundtable_knights", "recruitable_knights", "recruited_servants", "recruitable_servants"]:
		var arr = cm.get(arr_name)
		if arr == null:
			continue
		for c in arr:
			if not is_instance_valid(c):
				continue
			var impact = c.get("multi_romantisme_impact")
			if impact == null or impact == 0:
				continue
			c.set("multi_romantisme_impact", 0)
			fixed += 1
	if fixed > 0:
		_log("[PolyRomance] 已为 %d 名角色清除多人恋爱嫉妒惩罚" % fixed)


func _on_character_romance_updated(_character = null, _positive = null) -> void:
	_apply_polyamory()


# ==================== 功能 2：Gideon 婚姻锁绕过 ====================

func _on_story_loaded() -> void:
	var sc := get_node_or_null("/root/StoryController")
	if sc != null and sc.has_method("observe_variables"):
		sc.observe_variables(["gideon_married"], self, "_on_gideon_married_changed")
	_install_demission_filter()


func _on_gideon_married_changed(arg1 = null, arg2 = null) -> void:
	var value = arg2 if arg2 != null else arg1
	if value != true:
		return
	_gideon_really_married = true
	_save_config()
	if _bypass_marriage_lock:
		var sc := get_node_or_null("/root/StoryController")
		if sc != null:
			sc.set_variable("gideon_married", false)
			_log("[PolyRomance] 已绕过 Gideon 婚姻锁（仍可与他人结婚）")


# 结局时恢复 Gideon 已婚状态，保证婚姻结局文本正常显示
func _on_ending_triggered(_ending = null) -> void:
	if not _bypass_marriage_lock:
		return
	var married := _gideon_really_married
	if not married:
		var g = _find_character("gideon")
		if g != null:
			var sd = g.get("special_dialogues")
			if sd is Dictionary and sd.has(&"marriage"):
				var dlg = sd[&"marriage"]
				if is_instance_valid(dlg) and dlg.get("has_already_been_played") == true:
					married = true
	if married:
		var sc := get_node_or_null("/root/StoryController")
		if sc != null:
			sc.set_variable("gideon_married", true)
			_log("[PolyRomance] 结局：已恢复 Gideon 已婚状态")


# ==================== 功能 3：任务出战人数上限解除 ====================
# 圆桌开放期间把任务的 nb_requested_knights 临时提升到 10（场景槽位数），
# 圆桌结束时还原原值，任务结算使用原版数值，不影响评分与存档。

func _on_roundtable_opened(_a = null, _b = null) -> void:
	# 延迟到本帧末尾：原版 set_up 会在信号之后连接现有头像的 pressed，
	# 我们先补齐的话原版会对新头像重复连接报错
	call_deferred("_ensure_knight_vignettes")
	_vignette_retry_later()
	if not _quest_cap_enabled:
		return
	var qm := _quests_manager()
	if qm == null:
		return
	var raised := 0
	for arr_name in ["current_quests", "ongoing_quests", "newly_locked_quests", "starting_quests"]:
		var arr = qm.get(arr_name)
		if arr == null:
			continue
		for q in arr:
			if not is_instance_valid(q):
				continue
			var cur = q.get("nb_requested_knights")
			if cur == null:
				continue
			if not _quest_cap_originals.has(q):
				_quest_cap_originals[q] = cur
			if cur < QUEST_MAX_SLOTS:
				q.set("nb_requested_knights", QUEST_MAX_SLOTS)
				raised += 1
	if raised > 0:
		_log("[PolyRomance] 已为 %d 个任务解除出战人数上限（临时）" % raised)


func _on_roundtable_finished(_a = null) -> void:
	for q in _quest_cap_originals.keys():
		if is_instance_valid(q):
			q.set("nb_requested_knights", _quest_cap_originals[q])
	var n := _quest_cap_originals.size()
	_quest_cap_originals.clear()
	if n > 0:
		_log("[PolyRomance] 已还原 %d 个任务的出战人数（结算不受影响）" % n)


# ==================== 功能 4：The Wolf / Rufus 共存 ====================
# 原版在治愈狼形态时强制 The Wolf 离队。这里把 CharacterManager 的
# 离队处理从信号上断开，换成带过滤的版本：放行其他骑士，拦下 the_wolf。

func _install_demission_filter() -> void:
	if _demission_filter_installed or not _wolf_coexist:
		return
	var sc := get_node_or_null("/root/StoryController")
	var cm := _char_manager()
	if sc == null or cm == null:
		return
	var p = sc.get("parser")
	if p == null:
		return
	var original := Callable(cm, "_on_story_instruction_knight_demission")
	if not p.is_connected("story_instruction_knight_demission", original):
		return  # CharacterManager.set_up 尚未执行，稍后重试
	p.disconnect("story_instruction_knight_demission", original)
	p.connect("story_instruction_knight_demission", _on_knight_demission_filtered)
	_demission_filter_installed = true
	_log("[PolyRomance] The Wolf / Rufus 共存已启用")


func _remove_demission_filter() -> void:
	if not _demission_filter_installed:
		return
	var sc := get_node_or_null("/root/StoryController")
	var cm := _char_manager()
	if sc != null and cm != null:
		var p = sc.get("parser")
		var original := Callable(cm, "_on_story_instruction_knight_demission")
		if p != null:
			if p.is_connected("story_instruction_knight_demission", _on_knight_demission_filtered):
				p.disconnect("story_instruction_knight_demission", _on_knight_demission_filtered)
			if not p.is_connected("story_instruction_knight_demission", original):
				p.connect("story_instruction_knight_demission", original)
	_demission_filter_installed = false


func _on_knight_demission_filtered(character_name: String) -> void:
	if _wolf_coexist and character_name.strip_edges().to_lower() == "the_wolf":
		_log("[PolyRomance] 已阻止 The Wolf 离队（与人类 Rufus 共存）")
		return
	var cm := _char_manager()
	if cm != null and cm.has_method("_on_story_instruction_knight_demission"):
		cm._on_story_instruction_knight_demission(character_name)


# ==================== 功能 5：圆桌骑士头像扩展（>12 人） ====================
# 原版场景只预置了 12 个 KnightVignette，_set_up_knights 不会创建新头像，
# 第 13 名起的骑士看不到也选不了。圆桌打开时按实际骑士数复制补齐头像，
# 接好按钮组与选中信号；超过 12 人时底部棋子栏启用滑轮窗（选中居中滚动），
# 极端情况下 curved_hbox.gd 覆盖文件还会自动缩小排列并避开两侧 UI 遮挡。

func _ensure_knight_vignettes() -> void:
	var cm := _char_manager()
	if cm == null:
		return
	var knights = cm.get("roundtable_knights")
	if knights == null:
		return
	for rt in get_tree().get_nodes_in_group("RoundTable"):
		_top_up_knight_vignettes(rt, knights.size())
		_hook_vignette_window_signals(rt)
		_apply_vignette_window(rt)


func _vignette_retry_later() -> void:
	await get_tree().create_timer(1.5).timeout
	_ensure_knight_vignettes()


func _top_up_knight_vignettes(rt: Node, knight_count: int) -> void:
	var display = rt.get("knight_vignettes_display")
	if display == null:
		return
	var box = display.get("knight_vignettes")
	if box == null:
		return
	var missing: int = knight_count - box.get_child_count()
	if missing <= 0:
		return
	var template: Node = null
	for child in box.get_children():
		if child.get("vignette_button") != null:
			template = child
			break
	if template == null or not rt.has_method("_on_knight_vignette_pressed"):
		return
	var template_button = template.get("vignette_button")
	var added := 0
	for i in range(missing):
		var v: Node = template.duplicate()
		v.name = "KnightVignetteExtra%d" % (box.get_child_count() + i)
		box.add_child(v)
		v.set("is_button_pressed", false)
		v.set("disabled", false)
		for prop in ["lock", "away", "assigned", "training", "notification_discussion", "notification_level_up"]:
			var sub = v.get(prop)
			if sub != null:
				sub.visible = false
		var vb = v.get("vignette_button")
		if vb != null and template_button != null and template_button.button_group != null:
			vb.button_group = template_button.button_group
		var cb := Callable(rt, "_on_knight_vignette_pressed").bind(v)
		if not v.is_connected("pressed", cb):
			v.connect("pressed", cb)
		added += 1
	if added > 0:
		if rt.has_method("_set_up_knights"):
			rt._set_up_knights()
		_log("[PolyRomance] 圆桌骑士 %d 名，已补齐 %d 个选择头像" % [knight_count, added])


# ---- 底部棋子栏滑轮窗（>12 人） ----
# 12 人以内完全走原版。超过后只显示选中棋子前后各 5 个（共 11 个），
# 保持原版大小与间距（可见数 ≤12 时 curved_hbox 自动走原版路径）；
# 切换选中时窗口跟随滚动。中央立绘保持原版逻辑（只显示选中者），不干预。

const VIGNETTE_WINDOW_HALF := 5
var _last_vignette_window_log := ""

func _hook_vignette_window_signals(rt: Node) -> void:
	var display = rt.get("knight_vignettes_display")
	if display == null:
		return
	var box = display.get("knight_vignettes")
	if box == null:
		return
	for v in box.get_children():
		if v.has_meta("poly_pawn_hook") or not v.has_signal("pressed"):
			continue
		v.set_meta("poly_pawn_hook", true)
		v.connect("pressed", _on_vignette_window_pressed.bind(rt))


func _on_vignette_window_pressed(rt: Node) -> void:
	# 等两帧让原版选中状态落定后再滚动窗口
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(rt):
		_apply_vignette_window(rt)


func _apply_vignette_window(rt: Node) -> void:
	var cm := _char_manager()
	if cm == null:
		return
	var knights = cm.get("roundtable_knights")
	if knights == null:
		return
	var display = rt.get("knight_vignettes_display")
	if display == null:
		return
	var box = display.get("knight_vignettes")
	if box == null:
		return
	# 已分配骑士的头像（容器顺序即骑士顺序）
	var assigned := []
	for v in box.get_children():
		var k = v.get("knight")
		if k != null and is_instance_valid(k):
			assigned.append(v)
	if assigned.size() <= 12 or not _vignette_carousel:
		# 人数回落或滑轮窗关闭：只恢复我们自己隐藏的头像
		for v in box.get_children():
			if v.has_meta("poly_vhidden"):
				v.remove_meta("poly_vhidden")
				v.visible = true
		return
	var sel := 0
	var selected = rt.get("current_selected_knight")
	if selected != null and is_instance_valid(selected):
		for i in range(assigned.size()):
			if assigned[i].get("knight") == selected:
				sel = i
				break
	var window_size: int = VIGNETTE_WINDOW_HALF * 2 + 1
	var from: int = clamp(sel - VIGNETTE_WINDOW_HALF, 0, max(0, assigned.size() - window_size))
	var to: int = min(from + window_size - 1, assigned.size() - 1)
	var changed := 0
	for i in range(assigned.size()):
		var v = assigned[i]
		if i >= from and i <= to:
			if v.has_meta("poly_vhidden"):
				v.remove_meta("poly_vhidden")
				v.visible = true
				changed += 1
		else:
			if v.visible:
				v.visible = false
				changed += 1
			v.set_meta("poly_vhidden", true)
	if changed > 0:
		if box.has_method("layout_children"):
			box.layout_children()
		var key := "%d-%d/%d" % [from, to, assigned.size()]
		if key != _last_vignette_window_log:
			_last_vignette_window_log = key
			_log("[PolyRomance] 棋子滑轮窗：显示 %d-%d/%d" % [from, to, assigned.size()])


# ---- 任务槽位染色：区分原版槽位与模组新增槽位 ----
# 模组把任务出战上限临时提到 10 后，超出原版人数的槽位染淡蓝色，
# 鼠标悬停有说明；hover 灰化用的是 modulate，与 self_modulate 互不干扰。

const EXTRA_SLOT_TINT := Color(0.55, 0.8, 1.0)
var _slot_tint_running := false

func _start_slot_tint_loop() -> void:
	if _slot_tint_running:
		return
	_slot_tint_running = true
	while true:
		await get_tree().create_timer(0.5).timeout
		_tint_quest_slots()
		# 棋子滑轮窗持续校正：原版若干流程会重置头像显隐
		for rt in get_tree().get_nodes_in_group("RoundTable"):
			_apply_vignette_window(rt)


func _tint_quest_slots() -> void:
	for rt in get_tree().get_nodes_in_group("RoundTable"):
		var qps = rt.get("quest_presentation_section")
		if qps == null:
			continue
		var container = qps.get("knight_slots_container")
		if container == null:
			continue
		var quest = qps.get("selected_quest")
		var original := -1
		if quest != null and is_instance_valid(quest):
			original = _quest_cap_originals.get(quest, quest.get("nb_requested_knights"))
		var idx := -1
		for child in container.get_children():
			if not child is AspectRatioContainer:
				continue
			idx += 1
			if child.get_child_count() == 0:
				continue
			var slot = child.get_child(0)
			var is_extra: bool = original >= 0 and idx >= original and child.visible
			slot.self_modulate = EXTRA_SLOT_TINT if is_extra else Color.WHITE
			slot.tooltip_text = "模组新增槽位（超出原版出战人数）" if is_extra else ""


# ==================== 模组菜单 (F8) ====================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_panel()


func _toggle_panel() -> void:
	if _layer == null:
		return
	_layer.visible = not _layer.visible
	if _layer.visible:
		_refresh_rows()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	_layer.visible = false
	add_child(_layer)

	var panel := PanelContainer.new()
	# 右侧锚定，高度占屏 80%，永不超出屏幕
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.clip_contents = true
	_panel = panel
	_reposition_panel()
	get_viewport().size_changed.connect(_reposition_panel)
	_layer.add_child(panel)

	# 所有内容放进一个滚动容器，任何分辨率都能滚到
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "同心结 PolyRomance v%s  [F8 关闭]" % MOD_VERSION
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "解锁剧情后，在自由时间与角色相处即可触发。\n婚礼可对多名骑士重复举办。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_rows_box)

	vbox.add_child(HSeparator.new())

	var all_row := HBoxContainer.new()
	vbox.add_child(all_row)
	var all_plus := Button.new()
	all_plus.text = "全员浪漫 +3"
	all_plus.pressed.connect(_on_all_plus3)
	all_row.add_child(all_plus)
	var all_max := Button.new()
	all_max.text = "全员恋爱圆满"
	all_max.pressed.connect(_on_all_full_romance)
	all_row.add_child(all_max)

	var debug_btn := Button.new()
	debug_btn.text = "【调试】全员入队+数值拉满"
	debug_btn.tooltip_text = "招募全部骑士与仆人，浪漫/好感/等级/护甲拉满。仅供调试 UI 与剧情，建议在测试存档上使用。"
	debug_btn.add_theme_font_size_override("font_size", 13)
	debug_btn.pressed.connect(_on_debug_recruit_max)
	vbox.add_child(debug_btn)

	_lock_toggle = CheckButton.new()
	_lock_toggle.text = "绕过 Gideon 婚姻锁"
	_lock_toggle.tooltip_text = "允许已婚后再结婚；结局时自动恢复 Gideon 已婚状态"
	_lock_toggle.add_theme_font_size_override("font_size", 13)
	_lock_toggle.button_pressed = _bypass_marriage_lock
	_lock_toggle.toggled.connect(_on_lock_toggled)
	vbox.add_child(_lock_toggle)

	var quest_toggle := CheckButton.new()
	quest_toggle.text = "解除任务出战人数上限"
	quest_toggle.tooltip_text = "圆桌开放期间每个任务最多派 10 名骑士；结算前还原原版数值，不影响评分与存档"
	quest_toggle.add_theme_font_size_override("font_size", 13)
	quest_toggle.button_pressed = _quest_cap_enabled
	quest_toggle.toggled.connect(_on_quest_cap_toggled)
	vbox.add_child(quest_toggle)

	var wolf_toggle := CheckButton.new()
	wolf_toggle.text = "The Wolf / Rufus 共存"
	wolf_toggle.tooltip_text = "治愈狼形态时不强制 The Wolf 离队，两种形态同时留在队中"
	wolf_toggle.add_theme_font_size_override("font_size", 13)
	wolf_toggle.button_pressed = _wolf_coexist
	wolf_toggle.toggled.connect(_on_wolf_toggled)
	vbox.add_child(wolf_toggle)

	var carousel_toggle := CheckButton.new()
	carousel_toggle.text = "棋子栏滑轮窗（>12 人）"
	carousel_toggle.tooltip_text = "开启后只显示选中棋子前后各 5 个；关闭则全员缩小显示"
	carousel_toggle.add_theme_font_size_override("font_size", 13)
	carousel_toggle.button_pressed = _vignette_carousel
	carousel_toggle.toggled.connect(_on_carousel_toggled)
	vbox.add_child(carousel_toggle)

	var note := Label.new()
	note.text = "圆桌人数上限已由模组文件永久解除（99 人）；超过 12 人时底部棋子栏自动缩小排列。"
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

	vbox.add_child(HSeparator.new())

	var author := Label.new()
	author.text = "作者：茹鸦reyalp\n本模组为玩家自制，与官方 WILD WITS GAMES 无关；仅供学习交流，使用风险自负。\nhttps://github.com/ReyalpWondery/Sovereign-Tower-PolyRomanceMod"
	author.add_theme_font_size_override("font_size", 12)
	author.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(author)


func _reposition_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	var w: float = min(430.0, vp.x * 0.9)
	var h: float = vp.y * 0.8
	_panel.offset_left = - w - 10
	_panel.offset_right = -10
	_panel.offset_top = - h / 2.0
	_panel.offset_bottom = h / 2.0


# 诊断：把角色数据状态写入日志，排查"未进入游戏"误报
func _diag(context: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	_log("[Diag:%s] GameState=%s" % [context, gs])
	if gs == null:
		return
	var cm = gs.get("character_manager")
	_log("[Diag:%s] character_manager=%s" % [context, cm])
	if cm == null:
		return
	for arr_name in ["roundtable_knights", "recruitable_knights", "recruited_servants", "recruitable_servants"]:
		var arr = cm.get(arr_name)
		_log("[Diag:%s] %s size=%s" % [context, arr_name, str(arr.size()) if arr != null else "null"])
	var chars := _collect_romanceable()
	_log("[Diag:%s] romanceable=%d" % [context, chars.size()])
	var rk = cm.get("recruitable_knights")
	if rk != null and rk.size() > 0:
		var k = rk[0]
		_log("[Diag:%s] sample=%s sd_keys=%s" % [context, str(k.get("character_ink_id")), str(k.get("special_dialogues"))])


func _refresh_rows() -> void:
	if _rows_box == null:
		return
	_diag("F8")
	for child in _rows_box.get_children():
		child.queue_free()
	var chars := _collect_romanceable()
	if chars.is_empty():
		var empty := Label.new()
		empty.text = "（尚未进入游戏或未招募任何角色）"
		_rows_box.add_child(empty)
		return
	for c in chars:
		_rows_box.add_child(_make_row(c))


func _make_row(c) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var info := Label.new()
	info.custom_minimum_size = Vector2(130, 0)
	info.clip_text = true
	info.add_theme_font_size_override("font_size", 13)
	row.add_child(info)
	_update_row_label(info, c)

	var plus := Button.new()
	plus.text = "浪漫+3"
	plus.tooltip_text = "增加 3 点浪漫值"
	plus.add_theme_font_size_override("font_size", 13)
	plus.pressed.connect(func(): _on_plus3(c, info))
	row.add_child(plus)

	var sd = c.get("special_dialogues")
	if sd is Dictionary and sd.has(&"romance_completed"):
		var full := Button.new()
		full.text = "恋爱圆满"
		full.tooltip_text = "浪漫值拉满并解锁完整恋爱剧情"
		full.add_theme_font_size_override("font_size", 13)
		full.pressed.connect(func(): _on_full_romance(c, info))
		row.add_child(full)

	if sd is Dictionary and sd.has(&"marriage"):
		var wed := Button.new()
		wed.text = "举办婚礼"
		wed.tooltip_text = "解锁与该骑士的婚礼仪式（自由时间触发，可重复）"
		wed.add_theme_font_size_override("font_size", 13)
		wed.pressed.connect(func(): _on_wedding(c))
		row.add_child(wed)

	return row


func _update_row_label(info: Label, c) -> void:
	if not is_instance_valid(c):
		return
	var cur = c.get("current_romantism")
	var mx = c.get("max_romantism")
	info.text = "%s  %s/%s" % [_char_display_name(c), str(cur), str(mx)]


func _char_display_name(c) -> String:
	var id = c.get("character_ink_id")
	if id == null:
		return "?"
	return String(id).replace("_", " ").capitalize()


func _collect_romanceable() -> Array:
	var out: Array = []
	var cm := _char_manager()
	if cm != null:
		for arr_name in ["roundtable_knights", "recruitable_knights", "recruited_servants", "recruitable_servants"]:
			var arr = cm.get(arr_name)
			if arr == null:
				continue
			for c in arr:
				_try_add_romanceable(c, out)
	# 序章/主菜单时上面的数组会被存档模板清空；
	# 直接从角色描述文件目录补全（ResourceLoader 缓存保证与游戏共享同一实例）
	for dir in ["res://content/character_descriptors/knights/", "res://content/character_descriptors/servants/"]:
		for f in ResourceLoader.list_directory(dir):
			if not f.ends_with(".tres"):
				continue
			_try_add_romanceable(load(dir + f), out)
	return out


func _try_add_romanceable(c, out: Array) -> void:
	if not is_instance_valid(c) or c in out:
		return
	if c.get("is_dead") == true:
		return
	var sd = c.get("special_dialogues")
	if not (sd is Dictionary):
		return
	if sd.has(&"romance_completed") or sd.has(&"marriage"):
		out.append(c)


func _find_character(ink_id: String):
	var cm := _char_manager()
	if cm != null and cm.has_method("get_servant_from_name"):
		return cm.get_servant_from_name(ink_id)
	return null


# ==================== 菜单动作 ====================

func _on_plus3(c, info: Label) -> void:
	if is_instance_valid(c) and c.has_method("update_romance"):
		c.update_romance(3)
		if c.has_method("check_for_romance_completed"):
			c.check_for_romance_completed()
	_update_row_label(info, c)


func _on_full_romance(c, info: Label) -> void:
	if not is_instance_valid(c):
		return
	var mx = c.get("max_romantism")
	var cur = c.get("current_romantism")
	if mx != null and cur != null and c.has_method("update_romance"):
		c.update_romance(mx - cur)
	if c.has_method("check_for_romance_completed"):
		c.check_for_romance_completed()
	_update_row_label(info, c)


func _on_wedding(c) -> void:
	if not is_instance_valid(c):
		return
	var ink_id = String(c.get("character_ink_id"))
	var cm := _char_manager()
	var unlocked := false
	if cm != null and cm.has_method("unlock_special_dialogue"):
		for arr_name in ["roundtable_knights", "recruited_servants"]:
			var arr = cm.get(arr_name)
			if arr != null and c in arr:
				cm.unlock_special_dialogue(ink_id, &"marriage")
				unlocked = true
				break
	if not unlocked and c.has_method("unlock_dialogue"):
		c.unlock_dialogue(&"marriage")
	_log("[PolyRomance] 已解锁 %s 的婚礼仪式（自由时间可触发）" % ink_id)


func _on_all_plus3() -> void:
	for c in _collect_romanceable():
		if c.has_method("update_romance"):
			c.update_romance(3)
	_refresh_rows()


func _on_all_full_romance() -> void:
	for c in _collect_romanceable():
		_on_full_romance(c, Label.new())
	_refresh_rows()


# 【调试】一键全员入队 + 数值拉满，用于查看 UI 与剧情效果
func _on_debug_recruit_max() -> void:
	var cm := _char_manager()
	if cm == null:
		_log("[PolyRomance] 调试按钮：未进入游戏，忽略")
		return
	var recruited := 0
	var rk = cm.get("recruitable_knights")
	if rk != null and cm.has_method("_recruit_knight"):
		var rt_knights = cm.get("roundtable_knights")
		for k in rk.duplicate():
			if not is_instance_valid(k) or k.get("is_dead") == true:
				continue
			if rt_knights != null and k in rt_knights:
				continue
			var ink_id = k.get("character_ink_id")
			if ink_id == null:
				continue
			cm._recruit_knight(ink_id)
			recruited += 1
	var servants := 0
	var rs = cm.get("recruitable_servants")
	if rs != null and cm.has_method("recruit_servant"):
		for s in rs.duplicate():
			if is_instance_valid(s) and s.get("is_dead") != true:
				cm.recruit_servant(s)
				servants += 1
	var maxed := 0
	for arr_name in ["roundtable_knights", "recruitable_knights", "recruited_servants", "recruitable_servants"]:
		var arr = cm.get(arr_name)
		if arr == null:
			continue
		for c in arr:
			if not is_instance_valid(c):
				continue
			if c.get("max_romantism") != null:
				c.set("current_romantism", c.get("max_romantism"))
			if c.get("max_affinity") != null:
				c.set("current_affinity", c.get("max_affinity"))
			if c.get("current_level") != null:
				c.set("current_level", 15)  # Knight.MAX_LEVEL
			if c.get("max_armor") != null:
				c.set("current_armor", c.get("max_armor"))
			maxed += 1
	var seb := get_node_or_null("/root/SignalsEventBus")
	if seb != null and seb.has_signal("knight_stats_update_required"):
		seb.emit_signal("knight_stats_update_required")
	_apply_polyamory()
	_ensure_knight_vignettes()
	_refresh_rows()
	_log("[PolyRomance] 调试：新招募骑士 %d 名、仆人 %d 名，%d 个角色数值已拉满" % [recruited, servants, maxed])


func _on_lock_toggled(on: bool) -> void:
	_bypass_marriage_lock = on
	_save_config()
	if on:
		var sc := get_node_or_null("/root/StoryController")
		if sc != null and sc.get_variable("gideon_married") == true:
			sc.set_variable("gideon_married", false)


func _on_quest_cap_toggled(on: bool) -> void:
	_quest_cap_enabled = on
	_save_config()
	if not on:
		_on_roundtable_finished()  # 立即还原任何进行中的补丁
	else:
		_on_roundtable_opened()


func _on_wolf_toggled(on: bool) -> void:
	_wolf_coexist = on
	_save_config()
	if on:
		_install_demission_filter()
	else:
		_remove_demission_filter()


func _on_carousel_toggled(on: bool) -> void:
	_vignette_carousel = on
	_save_config()
	_ensure_knight_vignettes()


# ==================== 配置持久化 ====================

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_bypass_marriage_lock = cfg.get_value("mod", "bypass_marriage_lock", true)
	_gideon_really_married = cfg.get_value("mod", "gideon_really_married", false)
	_quest_cap_enabled = cfg.get_value("mod", "quest_cap_enabled", true)
	_wolf_coexist = cfg.get_value("mod", "wolf_coexist", true)
	_vignette_carousel = cfg.get_value("mod", "vignette_carousel", false)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("mod", "bypass_marriage_lock", _bypass_marriage_lock)
	cfg.set_value("mod", "gideon_really_married", _gideon_really_married)
	cfg.set_value("mod", "quest_cap_enabled", _quest_cap_enabled)
	cfg.set_value("mod", "wolf_coexist", _wolf_coexist)
	cfg.set_value("mod", "vignette_carousel", _vignette_carousel)
	cfg.save(CONFIG_PATH)
