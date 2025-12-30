## Main menu scene
extends Control
class_name MainMenu

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var connect_button: Button = $VBoxContainer/ConnectButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready():
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	print("[MainMenu] Start Server button pressed")
	# Start as host/server
	print("[MainMenu] Starting server via NetworkManager...")
	if NetworkManager:
		var success = NetworkManager.start_server(7777)
		if success:
			print("[MainMenu] ✓ Server started, switching to character select")
			# Go to character selection first
			get_tree().change_scene_to_file("res://scenes/CharacterSelectScene.tscn")
		else:
			print("[MainMenu] ✗ Failed to start server!")
	else:
		print("[MainMenu] ERROR: NetworkManager not found!")

func _on_connect_pressed():
	# Connect to server
	get_tree().change_scene_to_file("res://scenes/ConnectScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
