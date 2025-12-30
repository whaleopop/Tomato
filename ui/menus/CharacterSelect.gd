## Character selection menu
extends Control
class_name CharacterSelect

signal character_selected(character_data: CharacterData)

var available_characters: Array[CharacterData] = []
var selected_character: CharacterData = null

func get_selected_character() -> CharacterData:
	return selected_character

func _ready():
	_load_characters()
	_create_character_buttons()
	
	# Connect back button if exists
	var back_button = get_node_or_null("VBoxContainer/BackButton")
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

func _load_characters():
	# Load all character data
	available_characters = [
		TomatoCharacter.new(),
		CarrotCharacter.new(),
		PumpkinCharacter.new(),
		CornCharacter.new(),
		BroccoliCharacter.new(),
		BeetCharacter.new(),
		GreenPepperCharacter.new(),
		TurnipCharacter.new(),
	]

func _create_character_buttons():
	var container = VBoxContainer.new()
	add_child(container)
	
	for character in available_characters:
		var button = Button.new()
		button.text = character.character_name
		button.custom_minimum_size = Vector2(200, 50)
		button.pressed.connect(_on_character_selected.bind(character))
		container.add_child(button)

func _on_character_selected(character: CharacterData):
	selected_character = character
	print("[CharacterSelect] Character selected: %s" % character.character_name)
	character_selected.emit(character)

	# Store in GameManager for use in GameScene
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.selected_character = character
		print("[CharacterSelect] Stored character in GameManager")

	# Switch to game scene after selection
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")
