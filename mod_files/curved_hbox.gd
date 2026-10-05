@tool
extends Control

# 同心结 PolyRomance Mod 覆盖版本
# 12 人以内：布局计算与原版完全一致（间距公式、定位方式均未改动）。
# 超过 12 人总宽超出屏幕时：等比缩小各头像的基准尺寸后再按原版公式排列，
# 保证所有骑士可见可选（不改动节点 scale，避免与头像自带动画冲突）。

@export var curve: Curve = Curve.new()
@export var spacing: = 10.0
@export var curve_height: = 100.0

@export_range(0.0, 0.5) var curve_padding: = 0.2
@export var min_visual_width: = 300.0

func _ready():
	await get_tree().process_frame
	layout_children()
	child_entered_tree.connect(layout_children)
	child_exiting_tree.connect(layout_children)
	resized.connect(layout_children)
	_hook_blocking_panels()


# 任务面板开合/滑动时重新布局，避免面板打开瞬间挡住头像
func _hook_blocking_panels():
	var rts := get_tree().get_nodes_in_group("RoundTable")
	if rts.is_empty():
		return
	var rt = rts[0]
	for prop in ["quests_list", "quest_presentation_section", "end_phase_button"]:
		var panel = rt.get(prop)
		if not panel is Control:
			continue
		if panel.has_signal("item_rect_changed") and not panel.is_connected("item_rect_changed", layout_children):
			panel.connect("item_rect_changed", layout_children)
		if panel.has_signal("visibility_changed") and not panel.is_connected("visibility_changed", layout_children):
			panel.connect("visibility_changed", layout_children)

func layout_children(_arg = null):
	var children: = get_children().filter( func(c): return c is Control and c.visible)

	if children.is_empty():
		return

	# 与原版相同：按圆桌骑士总数计算间距（12 人封顶）
	spacing = lerp(20.0, -12.0, clamp(float(GameState.character_manager.roundtable_knights.size()), 0.0, 12.0) / 12.0)

	# 模组新增：超过 12 人时，先算出未被左侧任务面板和右下结束按钮遮挡的
	# 可用区间，再在该区间内排列；必要时等比缩小头像。
	# 12 人以内完全走原版路径（全宽、不缩小）。
	var region := Vector2(0.0, size.x)
	if children.size() > 12:
		region = _free_region()
	var available_width: = region.y - region.x
	if available_width <= 0.0:
		available_width = min_visual_width

	var fit_scale: = 1.0
	var base_unit: = 0.0
	for child in children:
		base_unit = max(base_unit, _base_size(child).x)
	if base_unit > 0.0:
		var raw_total: = base_unit * children.size() + spacing * (children.size() - 1.0)
		if raw_total > available_width:
			fit_scale = clamp(available_width / raw_total, 0.4, 1.0)

	if fit_scale < 1.0:
		for child in children:
			_apply_fit_scale(child, fit_scale)
	else:
		# 人数回落到不溢出时还原原版尺寸
		for child in children:
			if child.has_meta("poly_base_size"):
				_apply_fit_scale(child, 1.0)

	var eff_spacing: = spacing * fit_scale

	var total_width: = 0.0
	for child in children:
		total_width += child.size.x
	total_width += eff_spacing * (children.size() - 1)

	var visual_width = max(total_width, min_visual_width)
	var start_x = - total_width / 2.0
	var visual_start_x = - visual_width / 2.0
	var region_center: = (region.x + region.y) / 2.0

	var x_offset = start_x

	for child in children:
		var w = child.size.x
		var center_x = x_offset + w / 2.0

		var t = curve_padding + (1.0 - 2.0 * curve_padding) * ((center_x - visual_start_x) / visual_width)
		t = clamp(t, 0.0, 1.0)

		var y: = (curve.sample(t) - 0.5) * curve_height

		child.position = Vector2(
			center_x - w / 2.0 + region_center,
			y + size.y / 2.0
		)
		x_offset += w + eff_spacing


# 头像带内未被 UI 遮挡的水平区间（本地坐标）：
# 左侧避开任务列表/任务详情面板，右侧避开结束阶段按钮。
func _free_region() -> Vector2:
	var left := 0.0
	var right: = size.x
	var rts := get_tree().get_nodes_in_group("RoundTable")
	if rts.is_empty():
		return Vector2(left, right)
	var rt = rts[0]
	var my_rect := get_global_rect()
	for prop in ["quests_list", "quest_presentation_section"]:
		var panel = rt.get(prop)
		if not panel is Control:
			continue
		var r: Rect2 = panel.get_global_rect()
		if r.position.y < my_rect.end.y and r.end.y > my_rect.position.y:
			left = max(left, r.end.x - my_rect.position.x)
	var end_btn = rt.get("end_phase_button")
	if end_btn is Control:
		var rb: Rect2 = end_btn.get_global_rect()
		if rb.position.y < my_rect.end.y and rb.end.y > my_rect.position.y:
			right = min(right, rb.position.x - my_rect.position.x)
	return Vector2(clamp(left, 0.0, size.x), clamp(right, 0.0, size.x))


func _base_size(control: Control) -> Vector2:
	if not control.has_meta("poly_base_size"):
		var s: = control.size
		if s.x <= 0.0 or s.y <= 0.0:
			s = control.custom_minimum_size
		control.set_meta("poly_base_size", s)
	return control.get_meta("poly_base_size")


func _apply_fit_scale(child: Control, fit_scale: float) -> void:
	child.custom_minimum_size = _base_size(child) * fit_scale
	child.size = _base_size(child) * fit_scale
	for desc in child.find_children("*", "Control", true, false):
		if not desc.has_meta("poly_base_min"):
			if desc.custom_minimum_size == Vector2.ZERO:
				continue
			desc.set_meta("poly_base_min", desc.custom_minimum_size)
		desc.custom_minimum_size = desc.get_meta("poly_base_min") * fit_scale
