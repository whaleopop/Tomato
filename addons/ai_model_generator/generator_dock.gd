@tool
extends VBoxContainer
## Editor dock that drives tools/ai_models/generate.py (text/image -> GLB).
## The generator runs as a separate process; its stdout is read on a thread so the editor
## stays responsive. Protocol: "PROGRESS: <pct> <msg>", "RESULT: <path>", "ERROR: <msg>".

const SETTINGS_PATH = "user://ai_model_generator.cfg"
const SCRIPT_PATH = "res://tools/ai_models/generate.py"

var ai_root_edit: LineEdit
var prompt_edit: TextEdit
var image_edit: LineEdit
var name_edit: LineEdit
var style_option: OptionButton
var faces_spin: SpinBox
var cpu_check: CheckBox
var rig_check: CheckBox
var generate_button: Button
var progress_bar: ProgressBar
var status_label: Label
var log_view: RichTextLabel
var result_button: Button
var file_dialog: FileDialog

var _thread: Thread = null
var _err_thread: Thread = null
var _pid: int = -1
var _result_path: String = ""
var _busy: bool = false

func _ready():
	custom_minimum_size = Vector2(260, 0)
	add_theme_constant_override("separation", 6)

	var title = Label.new()
	title.text = "Local 3D generator (TripoSR)"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_add_caption("Describe the model (English):")
	prompt_edit = TextEdit.new()
	prompt_edit.placeholder_text = "broccoli knight with a tiny shield"
	prompt_edit.custom_minimum_size = Vector2(0, 64)
	prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(prompt_edit)

	_add_caption("...or start from an image:")
	var image_row = HBoxContainer.new()
	add_child(image_row)
	image_edit = LineEdit.new()
	image_edit.placeholder_text = "C:/path/to/concept.png"
	image_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_row.add_child(image_edit)
	var browse = Button.new()
	browse.text = "..."
	browse.pressed.connect(_on_browse)
	image_row.add_child(browse)

	var grid = GridContainer.new()
	grid.columns = 2
	add_child(grid)

	_grid_label(grid, "Name")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "auto"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(name_edit)

	_grid_label(grid, "Style")
	style_option = OptionButton.new()
	style_option.add_item("veggie")
	style_option.add_item("character")
	style_option.add_item("prop")
	style_option.add_item("none")
	grid.add_child(style_option)

	_grid_label(grid, "Faces")
	faces_spin = SpinBox.new()
	faces_spin.min_value = 0
	faces_spin.max_value = 100000
	faces_spin.step = 500
	faces_spin.value = 8000
	faces_spin.tooltip_text = "Target triangle count after decimation (0 = keep all)"
	grid.add_child(faces_spin)

	_grid_label(grid, "AI folder")
	ai_root_edit = LineEdit.new()
	ai_root_edit.text = "D:/royaltim-ai"
	ai_root_edit.tooltip_text = "Install root created by tools/ai_models/setup.ps1"
	grid.add_child(ai_root_edit)

	rig_check = CheckBox.new()
	rig_check.text = "Rig + animate in Blender (skeleton, walk/idle/attack...)"
	rig_check.button_pressed = true
	add_child(rig_check)

	cpu_check = CheckBox.new()
	cpu_check.text = "CPU only (slow, no GPU needed)"
	add_child(cpu_check)

	generate_button = Button.new()
	generate_button.text = "Generate"
	generate_button.custom_minimum_size = Vector2(0, 34)
	generate_button.pressed.connect(_on_generate)
	add_child(generate_button)

	progress_bar = ProgressBar.new()
	progress_bar.max_value = 100
	add_child(progress_bar)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Ready. A model takes ~40 s on an RTX 3050 Ti (first run longer)."
	add_child(status_label)

	result_button = Button.new()
	result_button.text = "Show result in FileSystem"
	result_button.visible = false
	result_button.pressed.connect(_on_show_result)
	add_child(result_button)

	log_view = RichTextLabel.new()
	log_view.custom_minimum_size = Vector2(0, 140)
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.scroll_following = true
	log_view.selection_enabled = true
	add_child(log_view)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	file_dialog.file_selected.connect(func(p): image_edit.text = p)
	add_child(file_dialog)

	_load_settings()

func _add_caption(text: String):
	var l = Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	add_child(l)

func _grid_label(grid: GridContainer, text: String):
	var l = Label.new()
	l.text = text
	grid.add_child(l)

func _on_browse():
	file_dialog.popup_centered_ratio(0.6)

func _python_path() -> String:
	return ai_root_edit.text.strip_edges().path_join("venv/Scripts/python.exe")

func _on_generate():
	if _busy:
		return
	var prompt = prompt_edit.text.strip_edges()
	var image = image_edit.text.strip_edges()
	if prompt == "" and image == "":
		_set_status("Enter a prompt or pick an image", true)
		return

	var python = _python_path()
	if not FileAccess.file_exists(python):
		_set_status("Python venv not found at %s. Run tools/ai_models/setup.ps1 first." % python, true)
		return

	var args = PackedStringArray(["-u", "-X", "utf8", ProjectSettings.globalize_path(SCRIPT_PATH)])
	if image != "":
		args.append_array(["--image", image])
	else:
		args.append_array(["--prompt", prompt, "--style", style_option.get_item_text(style_option.selected)])
	if name_edit.text.strip_edges() != "":
		args.append_array(["--name", name_edit.text.strip_edges()])
	args.append_array(["--faces", str(int(faces_spin.value))])
	if cpu_check.button_pressed:
		args.append("--cpu")
	if rig_check.button_pressed:
		args.append("--rig")

	# Blocking pipes, each drained by its own thread (an undrained stderr can stall the child)
	var info = OS.execute_with_pipe(python, args, true)
	if info.is_empty():
		_set_status("Could not start the generator process", true)
		return

	_save_settings()
	_busy = true
	_pid = info.get("pid", -1)
	_result_path = ""
	generate_button.disabled = true
	result_button.visible = false
	progress_bar.value = 0
	log_view.clear()
	_set_status("Starting... (~40 s, the first run loads the models longer)")

	_thread = Thread.new()
	_thread.start(_read_output.bind(info["stdio"]))
	_err_thread = Thread.new()
	_err_thread.start(_drain_stderr.bind(info["stderr"]))

## Runs on the worker thread
func _read_output(pipe: FileAccess):
	while pipe.is_open() and pipe.get_error() == OK:
		var line = pipe.get_line()
		if line == "" and pipe.eof_reached():
			break
		if line != "":
			call_deferred("_handle_line", line)
	call_deferred("_on_process_finished")

## Library warnings/tracebacks: shown dimmed in the log
func _drain_stderr(pipe: FileAccess):
	while pipe.is_open() and pipe.get_error() == OK:
		var line = pipe.get_line()
		if line == "" and pipe.eof_reached():
			break
		if line.strip_edges() != "":
			call_deferred("_append_dim", line)

func _append_dim(line: String):
	log_view.append_text("[color=#8a8f9c]%s[/color]
" % line.strip_edges())

func _handle_line(line: String):
	line = line.strip_edges()
	if line.begins_with("PROGRESS:"):
		var rest = line.substr(9).strip_edges()
		var space = rest.find(" ")
		var pct = rest.substr(0, space) if space > 0 else rest
		progress_bar.value = float(pct)
		if space > 0:
			_set_status(rest.substr(space + 1))
	elif line.begins_with("RESULT:"):
		_result_path = line.substr(7).strip_edges()
	elif line.begins_with("ERROR:"):
		_set_status(line.substr(6).strip_edges(), true)
		log_view.append_text("[color=#ff7070]%s[/color]\n" % line)
		return
	log_view.append_text(line + "\n")

func _on_process_finished():
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	if _err_thread:
		_err_thread.wait_to_finish()
		_err_thread = null
	_busy = false
	generate_button.disabled = false
	if _result_path != "":
		progress_bar.value = 100
		_set_status("Done: %s" % _result_path.get_file())
		result_button.visible = true
		EditorInterface.get_resource_filesystem().scan()
	elif not status_label.text.begins_with("!"):
		_set_status("Generator stopped without a result - see the log", true)

func _on_show_result():
	var res_path = ProjectSettings.localize_path(_result_path.replace("\\", "/"))
	if res_path.begins_with("res://"):
		EditorInterface.get_file_system_dock().navigate_to_path(res_path)
	else:
		OS.shell_open(_result_path.get_base_dir())

func _set_status(text: String, is_error: bool = false):
	status_label.text = ("! " if is_error else "") + text
	status_label.modulate = Color(1, 0.55, 0.55) if is_error else Color.WHITE

func _load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		ai_root_edit.text = cfg.get_value("generator", "ai_root", ai_root_edit.text)
		faces_spin.value = cfg.get_value("generator", "faces", faces_spin.value)

func _save_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("generator", "ai_root", ai_root_edit.text)
	cfg.set_value("generator", "faces", faces_spin.value)
	cfg.save(SETTINGS_PATH)

func _exit_tree():
	if _busy and _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	for t in [_thread, _err_thread]:
		if t and t.is_started():
			t.wait_to_finish()
