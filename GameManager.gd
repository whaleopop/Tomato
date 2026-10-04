## Main game manager (autoload): cross-scene match state
extends Node

var selected_character: CharacterData = null  # Character selected in CharacterSelect menu
var map_seed: int = 0  # Map seed for generation
var last_error: String = ""  # Shown by the main menu after a failed/lost connection
var training_mode: bool = false  # the game scene builds the training ground (TrainingGround)
var matchmaking: bool = false  # PLAY online: after the hero comes the queue (MatchmakingScreen)
var matchmaking_follow: bool = false  # in a party, not the leader: the leader's search took us along
var game_mode: String = "br"   # GameModes id: the host picks it, clients get it in the lobby state

# Cutscene data - set by SpawnSelectController / NetworkLobby before cutscene
var cutscene_spawn_positions: Dictionary = {}  # player_id -> Vector3
var cutscene_player_characters: Dictionary = {}  # player_id -> String
var cutscene_fast_forward: bool = false  # For late joiners
var cutscene_elapsed: float = 0.0  # Elapsed time for fast forward

func _ready():
	# NOTE: this autoload must NOT be in the "game_scene" group: code looks the game scene
	# up by that group and the autoload would always be found first.
	print("[GameManager] Ready")

## Forget everything about the previous match (keeps the selected character)
func reset_match_state():
	map_seed = 0
	cutscene_spawn_positions = {}
	cutscene_player_characters = {}
	cutscene_fast_forward = false
	cutscene_elapsed = 0.0
