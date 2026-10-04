extends Node
# [PolyRomance] class_name 已移除（全局类缓存按路径注册，避免重复声明冲突）

const CHARACTERS_PORTRAIT_FILEPATH: = "res://scenes/character_portraits/"

@export var traitors_plot_manager: TraitorsPlotManager
@export var intendant_manager: IntendantManager
@export_category("Servants")
@export var recruited_servants: Array[Servant] = []
@export var recruitable_servants: Array[Servant] = []
@export var romanced_characters: Dictionary[Servant, bool] = {}

@export_category("Knights")
@export var starting_knights: Array[Knight]
@export var recruitable_knights: Array[Knight]
@export var knights_recruitment_postponed_audiences: Dictionary[Knight, Audience] = {}

@export var knight_conversations: Array[KnightConversation]
@export var killable_characters: Array[Character]

var available_knight_conversations: Array[KnightConversation]
var roundtable_knights: Array[Knight]
var available_knights: Array[Knight]: get = _get_available_knights
var targets_killed: Array[StringName] = []
var all_characters_portraits_index: = []
var updated_knights: Array[Knight] = []
var deaths_count: Dictionary[Knight, int] = {}
var all_time_recruited_knights: Array[Knight] = []
var has_played_conversation: bool = false
var dialogue_played_this_cycle: int = 0

func set_up():
	load_characters_portrait_index()
	roundtable_knights = starting_knights.duplicate()
	available_knight_conversations = knight_conversations.duplicate()
	for knight in roundtable_knights:
		knight.set_up()
	if not StoryController.parser.story_instruction_unlock_tag.is_connected(_on_story_instruction_unlock_tag):
		StoryController.parser.story_instruction_unlock_tag.connect(_on_story_instruction_unlock_tag)
		StoryController.parser.story_instruction_knight_recruitment.connect(_on_story_instruction_knight_recruitment)
		StoryController.parser.story_instruction_knight_demission.connect(_on_story_instruction_knight_demission)
		StoryController.parser.story_instruction_update_knight_affinity.connect(_on_story_instruction_update_knight_affinity)
		StoryController.parser.story_instruction_update_servant_romance.connect(_on_story_instruction_update_servant_romance)
		StoryController.parser.story_instruction_unlock_special_dialogue.connect(_on_story_instruction_unlock_special_dialogue)
		StoryController.parser.story_instruction_kill_knight.connect(_on_story_instruction_kill_knight)
		StoryController.parser.story_instruction_new_character_romanced.connect(_on_story_instruction_new_character_romanced)
		SignalsEventBus.unlock_special_dialogue.connect(_on_unlock_special_dialogue)
		SignalsEventBus.affinity_reward_obtained.connect(_on_affinity_reward_obtained)
		SignalsEventBus.character_tag_reward_obtained.connect(_on_character_tag_reward_obtained)
		SignalsEventBus.knight_affinity_updated.connect(_on_knight_affinity_updated)
		SignalsEventBus.knight_conversation_started.connect(_on_knight_conversation_started)
		SignalsEventBus.knight_armor_reached_zero.connect(_on_knight_armor_reached_zero)
		SignalsEventBus.cycle_transition_finished.connect(_on_cycle_transition_finished)
		SignalsEventBus.sovereign_tag_choice_triggered.connect(_on_sovereign_tag_choice_triggered)
		SignalsEventBus.current_knight_demission_reward_obtained.connect(_on_current_knight_demission_reward_obtained)
		SignalsEventBus.character_death_reward_obtained.connect(_on_character_death_reward_obtained)
		SignalsEventBus.roundtable_finished.connect(_on_roundtable_finished)
		SignalsEventBus.ursula_coming_back_to_roundtable.connect(_on_ursula_coming_back_to_roundtable)
		SignalsEventBus.belladonna_hates_you.connect(_on_belladonna_hates_you)
		SignalsEventBus.victoria_betrayed.connect(_on_victoria_betrayed)
		SignalsEventBus.seduced_knight_freed.connect(_on_seduced_knight_freed)
		SignalsEventBus.seduced_knight_recruited.connect(_on_seduced_knight_recruited)
		SignalsEventBus.seduced_knight_later.connect(_on_seduced_knight_later)
		SignalsEventBus.knight_dimissed.connect(_on_knight_dismissed)
		SignalsEventBus.demon_room_set_up.connect(_on_demon_room_set_up)
	intendant_manager.set_up()

func load_characters_portrait_index():
	all_characters_portraits_index.clear()
	_scan_characters_dir(CHARACTERS_PORTRAIT_FILEPATH)

func get_available_affinity_dialogs() -> Dictionary[FreeTimeDialogue, Knight]:
	var available_affinity_dialogs: Dictionary[FreeTimeDialogue, Knight] = {}
	for knight: Knight in roundtable_knights:
		if not knight.is_available:
			continue
		if knight is Alwena:
			continue
		var knight_available_special_dialogue: FreeTimeDialogue = knight.get_available_special_dialogue()
		if not is_instance_valid(knight_available_special_dialogue):
			continue
		available_affinity_dialogs[knight_available_special_dialogue] = knight

	for knight: Knight in roundtable_knights:
		if available_affinity_dialogs.size() + dialogue_played_this_cycle >= 2:
			has_played_conversation = true
			break
		if not knight.is_available:
			continue
		if knight is Alwena:
			continue
		if knight in available_affinity_dialogs.values():
			continue
		var knight_available_affinity_dialogue: FreeTimeDialogue = knight.get_available_affinity_dialog()
		if not is_instance_valid(knight_available_affinity_dialogue):
			continue
		available_affinity_dialogs[knight_available_affinity_dialogue] = knight
	return available_affinity_dialogs

func pick_knight_conversation(excluded_knights: Array[Knight]) -> KnightConversation:
	if has_played_conversation:
		return null
	var eligible_knight_conversations: Array[KnightConversation] = []
	for knight_conversation in available_knight_conversations:
		var excluded_knight_in_dialogue: bool = false
		for knight: Character in knight_conversation.knights:
			if not knight is Knight and knight is Servant:
				continue
			if knight.has_already_spoken_this_cycle:
				excluded_knight_in_dialogue = true
				break
			if not knight.is_available:
				excluded_knight_in_dialogue = true
				break
			if not knight in excluded_knights and knight in roundtable_knights:
				continue
			excluded_knight_in_dialogue = true
			break
		if excluded_knight_in_dialogue:
			continue
		if not knight_conversation.are_conditions_matched():
			continue
		eligible_knight_conversations.append(knight_conversation)

	if eligible_knight_conversations.is_empty():
		return null

	return eligible_knight_conversations.front()

func get_equipped_equipments(filter: Equipment.EquipmentsTypes = Equipment.EquipmentsTypes.UNDEFINED) -> Dictionary[Equipment, Knight]:
	var equiped_equipements: Dictionary[Equipment, Knight] = {}
	for knight in roundtable_knights:
		match filter:
			Equipment.EquipmentsTypes.UNDEFINED:
				for equipment in knight.equipments:
					if not is_instance_valid(equipment):
						continue
					equiped_equipements[equipment] = knight
			Equipment.EquipmentsTypes.RELIC:
				if not is_instance_valid(knight.relic):
					continue

			Equipment.EquipmentsTypes.MOUNT:
				if not is_instance_valid(knight.mount):
					continue
				equiped_equipements[knight.mount] = knight
			Equipment.EquipmentsTypes.CONSUMABLE:
				if not is_instance_valid(knight.consumable):
					continue
				equiped_equipements[knight.consumable] = knight
	return equiped_equipements

func forge_heal_armor(character: Knight):
	if not is_instance_valid(character):
		return
	character.current_armor = character.get_max_armor_with_bonus()
	SignalsEventBus.knight_armor_repaired.emit(character)

func recruit_servant(servant: Servant):
	if not servant in recruitable_servants:
		return
	if servant in recruited_servants:
		return
	recruited_servants.append(servant)

func recruit_servant_from_id(id: StringName):
	var servant: Servant = get_servant_from_name(id)
	recruit_servant(servant)

func reveal_tag(affected_knight: Knight, tag_name: String, tag_type: String, _knight_name: String, with_continue_story: bool = false):
	affected_knight.reveal_tag(tag_name, tag_type, with_continue_story)

func get_roundtable_knight_from_name(knight_name: String) -> Knight:
	for knight in roundtable_knights:
		if knight_name.to_lower() != knight.character_ink_id:
			continue
		return knight
	if get_tree().current_scene is FreeTimeDialoguePlayground:
		for knight in recruitable_knights:
			if knight_name.to_lower() == knight.character_ink_id:
				return knight
	return null

func _scan_characters_dir(path: String) -> void :
	var resources: PackedStringArray = ResourceLoader.list_directory(path)
	if resources.is_empty():
		return

	for resource in resources:
		var res_path: String = path + resource
		if res_path.ends_with("/"):
			_scan_characters_dir(res_path)
			continue
		if not res_path.ends_with(".tscn"):
			continue

		var full_path = res_path
		var rel_path = full_path.replace(CHARACTERS_PORTRAIT_FILEPATH, "")
		var id = resource.to_lower().replace(".tscn", "")
		all_characters_portraits_index.append({
			"id": id, 
			"path": rel_path
		})


func _update_knight_affinity(knight: Knight, amount: float):
	if not is_instance_valid(knight):
		return
	knight.update_affinity(amount)
	if not knight in roundtable_knights:
		return
	SignalsEventBus.send_notification.emit(Notification.NOTIFICATION_TYPE.KNIGHT_AFFINITY_UPDATED, [knight, amount])

func _update_servant_romance(servant: Servant, amount: int):
	if not is_instance_valid(servant):
		return
	servant.update_romance(amount)

func _unlock_character_tag_for_knight(knight: Knight, character_tag: TagManager.CharacterTags, unknown_tag: bool):
	if not knight in roundtable_knights:
		return
	knight.add_characteristic(character_tag, unknown_tag)

func _recruit_knight(new_knight_name: String):
	var new_knight: Knight = null
	for knight in recruitable_knights:
		if new_knight_name.to_lower() != knight.character_ink_id:
			continue
		new_knight = knight
		break
	if not is_instance_valid(new_knight):
		return
	if new_knight in roundtable_knights:
		return

	new_knight.set_up()
	if not new_knight is Angelica:
		new_knight.has_already_spoken_this_cycle = true
	if not new_knight in all_time_recruited_knights:
		all_time_recruited_knights.append(new_knight)
	roundtable_knights.append(new_knight)
	if new_knight is Gwendan:
		new_knight.check_for_reform()
	SignalsEventBus.knight_recruited.emit(new_knight)
	SignalsEventBus.send_notification.emit(Notification.NOTIFICATION_TYPE.KNIGHT_RECRUITMENT, [new_knight.name, new_knight.pawn_texture])

func _remove_knight_from_roundtable(knight: Knight, is_dead: bool = false):
	if not knight in roundtable_knights:
		return
	roundtable_knights.erase(knight)

	if knight.assigned_quest:
		knight.assigned_quest.assigned_knights.erase(knight)
		knight.assigned_quest = null

	SignalsEventBus.knight_removed.emit(knight)
	var equipment_to_remove: Array[Equipment] = knight.equipments.duplicate()
	var demission_audience: Audience = load(knight.get_demission_path())
	knight.current_affinity = max(knight.demission_affinity_treshold + 1, knight.current_affinity)
	for i in range(GameState.current_cycle_index, GameState.cycles.size()):
		var cycle: Cycle = GameState.cycles[i]
		for audience: Audience in cycle.audiences.duplicate():
			if not is_instance_valid(audience):
				continue
			if audience.ink_path != demission_audience.ink_path:
				continue
			cycle.audiences.erase(audience)

	for equipment in knight.equipments:
		if not is_instance_valid(equipment):
			continue
		if not equipment.is_exclusive:
			continue
		equipment_to_remove.erase(equipment)

	GameState.inventory_manager.add_equipments_to_inventory(equipment_to_remove)
	if is_instance_valid(knight.consumable) and not knight.consumable.is_exclusive:
		knight.consumable = null
	if is_instance_valid(knight.relic) and not knight.relic.is_exclusive:
		knight.relic = null
	if is_instance_valid(knight.mount) and not knight.mount.is_exclusive:
		knight.mount = null
	if is_dead:
		return
	SignalsEventBus.send_notification.emit(Notification.NOTIFICATION_TYPE.KNIGHT_DEMISSION, [knight.name, knight.pawn_texture])

func _get_available_knights() -> Array[Knight]:
	var knights_to_return: Array[Knight]
	for knight in roundtable_knights:
		if not knight.is_available:
			continue
		knights_to_return.append(knight)

	return knights_to_return

func get_servant_from_name(servant_name: String) -> Servant:
	var knight: = get_knight_from_name(servant_name)
	if is_instance_valid(knight):
		return knight
	for servant in recruitable_servants:
		if servant_name.to_lower() != servant.character_ink_id:
			continue
		return servant
	return null

func get_knight_from_name(knight_name: String) -> Knight:
	for knight in recruitable_knights:
		if knight_name.to_lower() != knight.character_ink_id:
			continue
		return knight
	return get_roundtable_knight_from_name(knight_name)

func get_death_count(knight: Knight) -> int:
	if not knight in deaths_count:
		return 0
	return deaths_count[knight]

func unlock_special_dialogue(character_name: String, key: StringName):
	for array in [roundtable_knights, recruited_servants]:
		for servant: Servant in array:
			if servant.character_ink_id != character_name.to_lower():
				continue
			servant.unlock_dialogue(key)
			SignalsEventBus.servant_dialogue_unlocked.emit(servant)
			return

func get_roundtable_size_limit() -> int:
	# [PolyRomance] 圆桌人数上限解除（原版为 6/8/10）
	return 99

func has_space_at_roundtable():
	return roundtable_knights.size() < get_roundtable_size_limit()

func has_dead_knight() -> bool:
	for knight in recruitable_knights:
		if not knight.is_dead:
			continue
		return true
	return false

func _on_story_instruction_unlock_tag(knight_name: String, tag_name: String, tag_type: String):
	var affected_knight: Knight = get_roundtable_knight_from_name(knight_name)
	if not is_instance_valid(affected_knight):
		StoryController.continue_story()
		return
	reveal_tag(affected_knight, tag_name, tag_type, knight_name, true)



func _on_story_instruction_knight_recruitment(new_knight_name: String):
	if is_instance_valid(get_roundtable_knight_from_name(new_knight_name)):
		return
	_recruit_knight(new_knight_name)


func _on_story_instruction_knight_demission(leaving_knight_name: String):
	var leaving_knight: Knight = get_roundtable_knight_from_name(leaving_knight_name)
	if not is_instance_valid(leaving_knight):
		return
	_remove_knight_from_roundtable(leaving_knight)



func _on_story_instruction_update_knight_affinity(knight_name: String, amount: int):
	var affected_knight: Knight = get_knight_from_name(knight_name)
	if not is_instance_valid(affected_knight):
		return
	var float_amount: float = float(amount)
	if float_amount > 0.0:
		float_amount *= 1.5
	_update_knight_affinity(affected_knight, float_amount)

func _on_story_instruction_update_servant_romance(servant_name: String, amount: int):
	var affected_servant: Servant = get_servant_from_name(servant_name)
	if not is_instance_valid(affected_servant):
		return
	_update_servant_romance(affected_servant, amount)


func _on_affinity_reward_obtained(amount: int, affected_knight: Knight):
	if affected_knight.is_dead:
		return
	_update_knight_affinity(affected_knight, float(amount))

func _on_character_tag_reward_obtained(character_tag: TagManager.CharacterTags, assigned_knigts_to_quest: Array[Knight], unknown_tag: bool):
	for knight in assigned_knigts_to_quest:
		_unlock_character_tag_for_knight(knight, character_tag, unknown_tag)

func _on_knight_affinity_updated(knight: Knight, amount: float):
	_update_knight_affinity(knight, amount)

func _on_knight_conversation_started(knight_conversation: KnightConversation):
	has_played_conversation = true
	if not knight_conversation in available_knight_conversations:
		return
	available_knight_conversations.erase(knight_conversation)

func _on_knight_armor_reached_zero(knight: Knight):
	knight.die()
	await get_tree().process_frame
	_remove_knight_from_roundtable(knight, true)
	if not deaths_count.has(knight):
		deaths_count[knight] = 1
	else:
		deaths_count[knight] = deaths_count[knight] + 1

func _on_cycle_transition_finished():
	has_played_conversation = false
	dialogue_played_this_cycle = 0
	await SignalsEventBus.cycle_index_updated
	for knight: Knight in roundtable_knights:
		if knight is Angelica and \
		GameState.current_cycle_index >= 34 and \
		not has_dead_knight():
			knight.unlock_dialogue("golden_key")
		knight.check_for_demission()
		knight.set_armor_for_new_cycle()
		knight.check_for_romance_completed()
		if is_instance_valid(knight.consumable) and knight.consumable.nb_utilisation <= 0:
			knight.consumable = null
		for audience in GameState.current_cycle.audiences:
			if not knight in audience.characters:
				continue
			knight.has_already_spoken_this_cycle = true
		if is_instance_valid(knight.assigned_quest):
			continue
		knight.affinity_cooldown = max(0, knight.affinity_cooldown - 1)
	for knight in recruitable_knights:
		knight.has_eaten = false
		knight.has_already_spoken_this_cycle = knight in updated_knights
	updated_knights.clear()
	for servant in recruited_servants:
		servant.check_for_romance_completed()

func _on_sovereign_tag_choice_triggered(tag: TagManager.SovereignTags):
	for knight: Knight in roundtable_knights:
		if tag in knight.liked_sovereign_tags:
			_update_knight_affinity(knight, 0.35)
		elif tag in knight.disliked_sovereign_tags:
			_update_knight_affinity(knight, - 0.125)


func _on_current_knight_demission_reward_obtained(knight: Knight):
	_remove_knight_from_roundtable(knight)

func _on_story_instruction_unlock_special_dialogue(character_name: String, key: StringName):
	unlock_special_dialogue(character_name, key)


func _on_character_death_reward_obtained(target_id: String):
	if target_id in targets_killed:
		return
	var is_character_killable: bool = false
	for character: Character in killable_characters:
		if character.character_ink_id != target_id:
			continue
		is_character_killable = true
		character.is_dead = true
		break
	if not is_character_killable:
		return
	targets_killed.append(target_id)
	SignalsEventBus.character_killed.emit(target_id)

func _on_story_instruction_kill_knight(knight_name: String):
	var knight: Knight = get_knight_from_name(knight_name)
	if not is_instance_valid(knight):
		return
	knight.die()
	await get_tree().process_frame
	_remove_knight_from_roundtable(knight, true)
	SignalsEventBus.send_notification.emit(Notification.NOTIFICATION_TYPE.KNIGHT_DEMISSION, [knight.name, knight.pawn_texture])

func _on_roundtable_finished():
	await get_tree().process_frame
	for knight in roundtable_knights:

		if is_instance_valid(knight.assigned_quest):
			continue
		knight.current_armor = min(knight.max_armor, knight.current_armor + 1)

func _on_ursula_coming_back_to_roundtable(ursula: Knight):
	await SignalsEventBus.cycle_transition_finished
	_recruit_knight(ursula.character_ink_id)

func _on_belladonna_hates_you():
	var belladonna: Servant = get_servant_from_name("witch_belladonna")
	if not is_instance_valid(belladonna):
		return
	for dialogue in belladonna.special_dialogues.values():
		if not dialogue is FreeTimeDialogue:
			continue
		var free_time_dialogue: FreeTimeDialogue = dialogue as FreeTimeDialogue
		free_time_dialogue.has_already_been_played = true

func _on_victoria_betrayed():
	var victoria: Victoria = get_knight_from_name("victoria")
	var romanced: Knight = get_knight_from_name(victoria.targeted_knight_id)
	_remove_knight_from_roundtable(victoria)
	_remove_knight_from_roundtable(romanced)

func _on_seduced_knight_freed():
	GameState.cycles_manager.special_intervention_manager.seduced_knight_freed = true

func _on_unlock_special_dialogue(character_name: String, key: StringName):
	unlock_special_dialogue(character_name, key)

func _on_seduced_knight_recruited():
	var victoria: Victoria = get_knight_from_name("victoria")
	var romanced: Knight = get_knight_from_name(victoria.targeted_knight_id)
	_recruit_knight(romanced.character_ink_id)

func _on_seduced_knight_later():
	var victoria: Victoria = get_knight_from_name("victoria")
	var romanced: Knight = get_knight_from_name(victoria.targeted_knight_id)
	if romanced.call_back_audience_request.is_empty():
		return
	GameState.world_manager.unlock_audience_request(romanced.call_back_audience_request)

func _on_knight_dismissed(knight: Knight):
	if not is_instance_valid(knight):
		return
	_remove_knight_from_roundtable(knight)

func _on_demon_room_set_up():
	recruit_servant_from_id("demon")

func _on_story_instruction_new_character_romanced(character_id: String):
	var servant: = get_servant_from_name(character_id)
	romanced_characters[servant] = true

	for romanced_character in romanced_characters:
		if not romanced_character is Knight:
			continue
		if romanced_character.character_ink_id == character_id:
			continue
		if romanced_character.multi_romantisme_impact == 0:
			continue
		romanced_character.update_affinity(romanced_character.multi_romantisme_impact)
		SignalsEventBus.send_notification.emit(Notification.NOTIFICATION_TYPE.KNIGHT_AFFINITY_UPDATED, [romanced_character, romanced_character.multi_romantisme_impact])
