## Self-update of the Windows build from the GitHub releases (CI publishes Royaltim-windows.zip on
## every "v*" tag, .github/workflows/build.yml). MainMenu asks `UpdateDialog.check()` at start; a
## newer tag than MainMenu.VERSION pops this dialog: UPDATE downloads the zip (progress bar),
## unpacks it into user://update/files, writes a small batch file that waits for this process to
## end, copies the files over the game folder and starts the game again, runs it and quits.
## Only in an exported game (not in the editor, not on a server); `--update-from=<dir>` (after --)
## pretends the game lives there (tests).
extends Control
class_name UpdateDialog

const REPO_API = "https://api.github.com/repos/whaleopop/Tomato/releases/latest"
const ASSET = "Royaltim-windows.zip"
const ZIP_ROOT = "Royaltim/"  # the folder inside the zip
const WORK = "user://update"

var release: Dictionary = {}  # tag, notes, url, size
var _title: Label
var _info: Label
var _bar: ProgressBar
var _update_button: Button
var _later_button: Button
var _http: HTTPRequest

## Where the game is installed ("" when there is nothing to update: editor, server, not Windows)
static func install_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--update-from="):
			return arg.substr(14)
	if OS.has_feature("editor") or not OS.has_feature("template") or OS.get_name() != "Windows" or DedicatedServer.requested():
		return ""
	return OS.get_executable_path().get_base_dir()

## "v0.8.1" > "v0.8.0"?
static func is_newer(tag: String, current: String) -> bool:
	var a = tag.trim_prefix("v").split(".")
	var b = current.trim_prefix("v").split(".")
	for i in maxi(a.size(), b.size()):
		var x = int(a[i]) if i < a.size() else 0
		var y = int(b[i]) if i < b.size() else 0
		if x != y:
			return x > y
	return false

## The latest release if it is newer than `current` and has the Windows zip, else {}
static func check(owner: Node, current: String) -> Dictionary:
	if install_dir() == "":
		return {}
	var http = HTTPRequest.new()
	http.timeout = 8.0
	owner.add_child(http)
	if http.request(REPO_API, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Royaltim"])) != OK:
		http.queue_free()
		return {}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return {}
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary or not is_newer(String(data.get("tag_name", "")), current):
		return {}
	for a in data.get("assets", []):
		if String(a.get("name", "")) == ASSET:
			return {"tag": String(data.tag_name), "notes": String(data.get("body", "")), "url": String(a.browser_download_url), "size": int(a.get("size", 0))}
	return {}

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.create_panel(center, 30)
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title = UITheme.create_title("UPDATE AVAILABLE", col)
	_title.add_theme_font_override("font", UITheme.font_black())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var version = UITheme.create_heading("%s  →  %s" % [MainMenu.VERSION, release.get("tag", "")], col)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", UITheme.ACCENT_PRIMARY)
	var notes = UITheme.create_label(_short_notes(String(release.get("notes", ""))), col, UITheme.FONT_SMALL)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	_info = UITheme.create_label(tr("Download: %.0f MB") % (release.get("size", 0) / 1048576.0), col, UITheme.FONT_SMALL)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar = UITheme.create_progress_bar(1.0, 0.0, UITheme.ACCENT_PRIMARY, col)
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.visible = false
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	_later_button = UITheme.create_button("LATER", row, Vector2(170, 54))
	_later_button.pressed.connect(queue_free)
	_update_button = UITheme.create_primary_button("UPDATE", row, Vector2(220, 58))
	_update_button.pressed.connect(_download)

func _short_notes(text: String) -> String:
	var lines = text.strip_edges().split("\n")
	return "\n".join(lines.slice(0, 12))

func _download():
	_update_button.disabled = true
	_later_button.disabled = true
	_bar.visible = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK))
	_http = HTTPRequest.new()
	_http.download_file = WORK + "/" + ASSET
	_http.download_chunk_size = 262144
	add_child(_http)
	_http.request_completed.connect(_on_downloaded)
	if _http.request(String(release.url), PackedStringArray(["User-Agent: Royaltim"])) != OK:
		_fail("Could not start the download")

func _process(_delta: float):
	if _http and is_instance_valid(_http) and _http.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total = maxi(_http.get_body_size(), 1)
		_bar.max_value = total
		_bar.value = _http.get_downloaded_bytes()
		_info.text = tr("Downloading: %.1f / %.1f MB") % [_http.get_downloaded_bytes() / 1048576.0, total / 1048576.0]

func _on_downloaded(result: int, code: int, _headers, _body):
	_http.queue_free()
	_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Download failed")
		return
	_info.text = tr("Installing...")
	await get_tree().process_frame
	var err = unpack()
	if err != "":
		_fail(err)
		return
	apply(true)

## The zip -> user://update/files (the game's own files can't be written while it runs)
func unpack() -> String:
	var files_dir = ProjectSettings.globalize_path(WORK + "/files")
	_remove_dir(files_dir)
	var zip = ZIPReader.new()
	if zip.open(WORK + "/" + ASSET) != OK:
		return "The download is damaged"
	var count = 0
	for path in zip.get_files():
		if not path.begins_with(ZIP_ROOT) or path.ends_with("/"):
			continue
		var target = files_dir.path_join(path.trim_prefix(ZIP_ROOT))
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f = FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "Could not unpack the update"
		f.store_buffer(zip.read_file(path))
		f.close()
		count += 1
	zip.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORK + "/" + ASSET))
	return "" if count > 0 else "The download is empty"

## Hand over to the batch file: wait for us to exit, copy, start the new game
func apply(restart: bool) -> void:
	var dir = install_dir().replace("/", "\\")
	var files = ProjectSettings.globalize_path(WORK + "/files").replace("/", "\\")
	var bat_path = ProjectSettings.globalize_path(WORK + "/apply_update.bat")
	var exe = dir + "\\" + OS.get_executable_path().get_file() if not OS.has_feature("editor") else dir + "\\Royaltim.exe"
	var bat = "\r\n".join([
		"@echo off",
		"chcp 65001 >nul",
		":wait",
		"tasklist /FI \"PID eq %d\" 2>nul | find \"%d\" >nul && (timeout /t 1 /nobreak >nul & goto wait)" % [OS.get_process_id(), OS.get_process_id()],
		"xcopy /E /Y /Q /I \"%s\\*\" \"%s\\\" >nul" % [files, dir],
		"rmdir /S /Q \"%s\"" % files,
		("start \"\" \"%s\"" % exe) if restart else "rem no restart",
		"",
	])
	var f = FileAccess.open(bat_path, FileAccess.WRITE)
	f.store_string(bat)
	f.close()
	OS.create_process("cmd.exe", ["/c", bat_path])
	get_tree().quit()

func _fail(reason: String):
	_info.text = tr(reason)
	_info.add_theme_color_override("font_color", UITheme.ACCENT_DANGER)
	_bar.visible = false
	_later_button.disabled = false

func _remove_dir(path: String):
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
