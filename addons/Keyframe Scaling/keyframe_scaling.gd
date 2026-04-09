@tool
extends EditorPlugin

var inspector_plugin

func _enter_tree():
	inspector_plugin = ScaleInspectorPlugin.new(self)
	add_inspector_plugin(inspector_plugin)

func _exit_tree():
	remove_inspector_plugin(inspector_plugin)


class ScaleInspectorPlugin extends EditorInspectorPlugin:

	var plugin

	func _init(p):
		plugin = p

	func _can_handle(object):
		return object is AnimationPlayer

	func _parse_begin(object):
		var button = Button.new()
		button.text = "Scale Animation Keys"
		button.icon = plugin.get_editor_interface().get_base_control().get_theme_icon("Time", "EditorIcons")
		button.tooltip_text = "Scale keyframes to a target duration"
		
		button.pressed.connect(func():
			plugin._open_dialog(object)
		)

		add_custom_control(button)


# ---------------- MAIN LOGIC ----------------

func _open_dialog(player: AnimationPlayer) -> void:
	if player.assigned_animation.is_empty():
		_show_message("No animation assigned", true)
		return

	var animation = player.get_animation(player.assigned_animation)
	if animation == null:
		_show_message("Animation not found", true)
		return

	var dialog = ConfirmationDialog.new()
	dialog.title = "Scale Animation"

	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	var label = Label.new()
	label.text = "Current length: " + str(animation.length) + " sec"
	vbox.add_child(label)

	var spin = SpinBox.new()
	spin.min_value = 0.001
	spin.max_value = 600.0
	spin.step = 0.001
	spin.value = animation.length
	spin.rounded = false
	vbox.add_child(spin)

	var only_selected_checkbox = CheckBox.new()
	only_selected_checkbox.text = "Only selected tracks"
	vbox.add_child(only_selected_checkbox)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	vbox.add_child(scroll)

	var track_list = VBoxContainer.new()
	scroll.add_child(track_list)

	var track_checkboxes = []

	for i in range(animation.get_track_count()):
		var cb = CheckBox.new()
		cb.text = str(animation.track_get_path(i))
		cb.button_pressed = true
		track_list.add_child(cb)
		track_checkboxes.append(cb)

	dialog.confirmed.connect(func():
		_scale_animation(
			animation,
			spin.value,
			only_selected_checkbox.button_pressed,
			track_checkboxes
		)
	)

	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()


func _scale_animation(animation: Animation, target_length: float, only_selected: bool, track_checkboxes: Array) -> void:
	var undo_redo: EditorUndoRedoManager = get_undo_redo()

	var original_length = animation.length

	if is_zero_approx(original_length) or is_zero_approx(target_length):
		_show_message("Invalid duration", true)
		return

	var ratio = target_length / original_length

	undo_redo.create_action("Scale Animation")

	for track_idx in range(animation.get_track_count()):
		
		if only_selected and not track_checkboxes[track_idx].button_pressed:
			continue

		var key_count = animation.track_get_key_count(track_idx)
		if key_count == 0:
			continue

		var old_keys = []
		var new_keys = []

		for i in range(key_count):
			var time = animation.track_get_key_time(track_idx, i)
			var value = animation.track_get_key_value(track_idx, i)
			var transition = animation.track_get_key_transition(track_idx, i)

			old_keys.append({
				"time": time,
				"value": value,
				"transition": transition
			})

			new_keys.append({
				"time": time * ratio,
				"value": value,
				"transition": transition
			})

		undo_redo.add_do_method(self, "_apply_keys", animation, track_idx, new_keys)
		undo_redo.add_undo_method(self, "_apply_keys", animation, track_idx, old_keys)

	undo_redo.add_do_property(animation, "length", target_length)
	undo_redo.add_undo_property(animation, "length", original_length)

	undo_redo.commit_action()

	_show_message("Animation scaled", false)


func _apply_keys(animation: Animation, track_idx: int, keys: Array) -> void:
	while animation.track_get_key_count(track_idx) > 0:
		animation.track_remove_key(track_idx, 0)

	for k in keys:
		animation.track_insert_key(
			track_idx,
			k["time"],
			k["value"],
			k["transition"]
		)


func _show_message(text: String, is_error: bool) -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = text
	dialog.title = "Error" if is_error else "Info"
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
