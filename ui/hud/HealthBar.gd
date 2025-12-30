## Health bar UI component
extends Control
class_name HealthBar

var health_bar: ProgressBar = null
var health_label: Label = null

var health_component: HealthComponent = null

func _ready():
	# Try to get existing nodes, create if they don't exist
	health_bar = get_node_or_null("HealthBar")
	if health_bar == null:
		health_bar = ProgressBar.new()
		health_bar.name = "HealthBar"
		health_bar.custom_minimum_size = Vector2(200, 20)
		health_bar.position = Vector2(10, 10)
		health_bar.max_value = 100.0
		health_bar.value = 100.0
		add_child(health_bar)
	
	health_label = get_node_or_null("HealthLabel")
	if health_label == null:
		health_label = Label.new()
		health_label.name = "HealthLabel"
		health_label.position = Vector2(10, 35)
		health_label.text = "100 / 100"
		add_child(health_label)

func setup(p_health_component: HealthComponent):
	health_component = p_health_component
	
	if health_component:
		health_component.health_changed.connect(_on_health_changed)
		_update_health()

func _on_health_changed(current: float, max_health: float):
	_update_health()

func _update_health():
	if not health_component:
		return
	
	if not health_bar:
		return
	
	var percent = health_component.get_health_percent()
	health_bar.value = percent * 100.0
	
	if health_label:
		health_label.text = "%d / %d" % [int(health_component.current_health), int(health_component.max_health)]
