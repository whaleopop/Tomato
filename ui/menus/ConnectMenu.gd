## Connect to server menu
extends Control
class_name ConnectMenu

@onready var ip_input: LineEdit = $VBoxContainer/IPInput
@onready var port_input: LineEdit = $VBoxContainer/PortInput
@onready var connect_button: Button = $VBoxContainer/ConnectButton
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready():
	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Set default values
	if ip_input:
		ip_input.text = "127.0.0.1"
	if port_input:
		port_input.text = "7777"
	
func _on_connect_pressed():
	print("[ConnectMenu] Connect button pressed")
	var ip = ip_input.text if ip_input else "127.0.0.1"
	var port = int(port_input.text) if port_input and port_input.text != "" else 7777
	
	print("[ConnectMenu] Connection parameters: IP=%s, Port=%d" % [ip, port])
	
	if status_label:
		status_label.text = "Connecting..."
	
	if NetworkManager:
		print("[ConnectMenu] Starting client connection via NetworkManager...")
		var success = NetworkManager.start_client(ip, port)
		
		if success:
			print("[ConnectMenu] Client connection initiated, waiting for game_client...")
			# Connect to game_client signals after it's created
			await get_tree().process_frame
			if NetworkManager.game_client:
				print("[ConnectMenu] GameClient found, connecting signals...")
				NetworkManager.game_client.connected_to_server.connect(_on_connected)
				NetworkManager.game_client.connection_failed.connect(_on_connection_failed)
				print("[ConnectMenu] ✓ Signals connected, waiting for connection result...")
			else:
				print("[ConnectMenu] ERROR: GameClient not found after creation!")
				if status_label:
					status_label.text = "Error: Client not created"
		else:
			print("[ConnectMenu] ✗ Failed to start client connection!")
			if status_label:
				status_label.text = "Failed to start connection"
	else:
		print("[ConnectMenu] ERROR: NetworkManager not found!")
		if status_label:
			status_label.text = "Error: NetworkManager missing"

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")

func _on_connected():
	print("[ConnectMenu] ✓ Connection successful! Switching to character select...")
	if status_label:
		status_label.text = "Connected!"
	# Switch to character selection (same as host flow)
	get_tree().change_scene_to_file("res://scenes/CharacterSelectScene.tscn")

func _on_connection_failed():
	print("[ConnectMenu] ✗ Connection failed!")
	if status_label:
		status_label.text = "Connection failed!"
