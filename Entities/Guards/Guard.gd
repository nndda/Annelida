extends CharacterBody2D

# Base scene for ALL entities

@export_category("Stats")

@export var health : float = 50.0
@export_range(1.25, 17.50, 0.25) var speed : float = 10.0
var speed_init : float

@export_range(0.0, 1.0) var knockback_mult        : float = 1.0

@export_range(0.0, 5.0, 0.1) var init_cooldown    : float = 0.0
@export_range(0.8, 5.0, 0.1) var cooldown_min     : float = 0.8
@export_range(0.8, 5.0, 0.1) var cooldown_max     : float = 0.8

@onready var cooldown_timer : Timer = $AttackCooldown
var cooldown_timer_left : float = 0.0

@export_category("Configurations")

## Stop aiming to player if firing
@export var freeze_on_fire := false

@export var keep_player_distance : float = 190.0

## Is the entity moving away or approaching the player's head.
@export var moving_away := false

## Is the entity able to move.
@export var stationary := false
@export var stationary_follow_rotate := false

## Is the entity immune to any damage (invincible).
@export var immune := false

## If true, the entity will only be triggered by manually emitting the [signal triggered] signal. Or by calling the [method damage] function.
@export var manual_trigger := false

@export_range(0.0, 1.0)\
var rotate_weight : float = 0.12
var rotate_weight_init : float

@export_group("Nodes")

## Designated 'patrol' path for non-stationary entity. Entity will not follow their path once triggered
@export var path : PathFollow2D

## Custom Area2D trigger that will detect player. Replaced the default TriggerArea node
@export var custom_trigger : Area2D

## Weapon scene for the entity
@export var weapon : Node2D

## The 'death scene' for when the entity is killed or destroyed
@export var corpse : Node2D

#@export var weapon_collision_exceptions : Array[CollisionObject2D]

## Particle scene for when the entity is attacked or damaged by the player
@export_file("*.tscn") var blood_scene : String = "res://Shaders/Particles/BloodSplatters.tscn"; var blood : Node

var is_triggered    := false
var firing          := false
signal triggered
signal killed

var fire_clear  := false
var fire_ready  := false
var clear       := true
var player_near := false

@warning_ignore("unused_signal")
signal path_changed(path)
@warning_ignore("unused_signal")
signal target_reached
@onready var nav_agent : NavigationAgent2D = $NavigationAgent2D

var velo            : Vector2
var move_direction  : Vector2
var player_angle    : float

@onready var sprite_base : Sprite2D = $Sprite2D
@onready var visibility_handler_enabler : VisibleOnScreenEnabler2D = $VisibilityHandler/VisibleOnScreenEnabler2D

func _enter_tree() -> void:
    if !is_in_group(&"free"):
        await weapon.tree_entered
        weapon.entity_holder = self

func _ready() -> void:
    if !is_in_group(&"free"):
        rotate_weight_init = rotate_weight
        speed_init = speed

        corpse.reparent(Global.layer_dict[^"Objects/Corpses"])

        corpse.modulate.a       = 0.8
        corpse.z_as_relative    = false
        corpse.z_index          = -100

        if corpse.get(&"blood_trail_trigger") != null:
            corpse.blood_trail_trigger.monitoring = false

        clear = init_cooldown == 0.0
        cooldown_timer.wait_time = randf_range(
            cooldown_min, cooldown_max
        )

        if !manual_trigger:
            if custom_trigger != null:
                custom_trigger.collision_mask = $TriggerArea.collision_mask
                custom_trigger.body_entered.connect(_on_trigger_body_entered)
                $TriggerArea.queue_free()
        else:
            $TriggerArea.queue_free()

        Global.camera_shaken_by_player.connect(trigger_if_near)

        if stationary:
            nav_agent = null
            for free_itms : Node in [ $KeepDistance, $KeepMove, $NavigationAgent2D ]:
                free_itms.queue_free()

        else:
            for hidden_item : Node in [ $KeepDistance, $KeepMove ]:
                hidden_item.visible = false

        #for n in weapon_collision_exceptions:
            #weapon.add_raycast_exception

        visibility_handler_enabler.global_position = global_position

func _process(_delta : float) -> void:
    corpse.global_position = global_position
    corpse.look_at(Global.head_pos)

    if is_triggered:

        if freeze_on_fire:
            if !firing:
                aim_to_player()
        else:
            aim_to_player()

        fire_clear = fire_ready and weapon.on_line

    else:
        if path != null:
            global_position = path.global_position
            global_rotation = path.global_rotation

    if stationary:
        if !stationary_follow_rotate:
            sprite_base.rotation_degrees = -rotation_degrees
    else:
        visibility_handler_enabler.global_position = global_position

    if fire_clear:
        if cooldown_timer.time_left <= 0.0:
            cooldown_timer.start()
        weapon.fire()
        fire_ready = false


    cooldown_timer_left = cooldown_timer.time_left
    lfire_coll = weapon.fire_function.line_of_fire.is_colliding()
    lsight_coll = weapon.line_of_sight.is_colliding()
    lobst_coll = weapon.obstacle_sight.is_colliding()
    on_line = weapon.on_line
    has_obstacle = weapon.has_obstacle

# TODO:  trigger system is a mess
func _physics_process(_delta : float) -> void:
    if is_triggered:
        if !stationary:
            #nav_agent.set_velocity(Vector2(80.0, 80.0))
            nav_agent.set_velocity(Vector2(speed, speed))

            #if weapon.has_obstacle or !weapon.player_on_sight:
                #look_target = nav_agent.get_next_path_position()
            #else:
                #look_target = Global.head_pos

#var look_target : Vector2
func aim_to_player() -> void:
    player_angle = (Global.head_pos - global_position).angle()
    global_rotation = lerp_angle(global_rotation, player_angle, rotate_weight)
    rotation_degrees = wrapf(rotation_degrees, 0.0, 360.0)

func _on_weapon_animation_started(anim : StringName) -> void:
    if anim == &"Firing":
        cooldown_timer.stop()
func _on_weapon_animation_finished(anim : StringName) -> void:
    if anim == &"Firing":
        cooldown_timer.start(randf_range(
            cooldown_min, cooldown_max
        ))
func _on_attack_cooldown_timeout() -> void:
    fire_ready = true

func damage(power : float) -> void:
    if !is_triggered:
        triggered.emit()

    if !immune:
        health -= power

        if health <= 0:
            kill()

        if power > 0.0:
            # blood particle
            blood = load(blood_scene).instantiate()
            blood.custom_init_pos = true
            blood.init_pos = global_position
            Global.layer_dict[^"Objects/Particles"].add_child(blood)

            # knockback
            effect_knockback(power * knockback_mult)

var is_killed := false
func kill() -> void:
    if !is_killed:
        is_killed = true
        corpse.z_as_relative = true
        corpse.z_index = 0
        corpse.visible = true

        if corpse.get(&"blood_trail_trigger") != null:
            corpse.blood_trail_trigger.monitoring = true

        killed.emit()
        queue_free()

# TODO:  navigation is a mess
var arrived := false
func set_target_pos(pos : Vector2) -> void:
    arrived = false
    nav_agent.target_position = pos

var direction : Vector2
func _on_navigation_velocity_computed(safe_velocity : Vector2) -> void:
    if !nav_agent.is_navigation_finished():
        velocity = safe_velocity * direction * speed
        move_and_slide()
    elif !arrived:
        arrived = true
        nav_agent.path_changed.emit()

@onready var keep_distance : Node2D = $KeepDistance
@onready var keep_distance_pos : Node2D = $KeepDistance/Position2D
@onready var keep_distance_a : Node2D = $KeepDistance/n1
@onready var keep_distance_b : Node2D = $KeepDistance/n2
@onready var keep_move_a : Node2D = $KeepMove/n1
@onready var keep_move_b : Node2D = $KeepMove/n2

func _on_update_player_pos_timeout() -> void:
    if global_position.distance_to(Global.head_pos) >= keep_player_distance:
        if !moving_away:
            direction = global_position.direction_to(Global.head_pos)
            set_target_pos(Global.head_pos)
    else:
        keep_distance.rotation_degrees = randf_range(-15.0, 15.0)
        keep_distance_pos.position = Vector2(
            randf_range(keep_distance_a.position.x, keep_distance_b.position.x),
            randf_range(keep_move_a.position.y, keep_move_b.position.y)
        )
        direction = global_position.direction_to(keep_distance_pos.global_position)
        set_target_pos(keep_distance_pos.global_position)

func trigger_if_near(substantial : bool) -> void:
    if player_near and substantial:
        triggered.emit()

func _on_trigger_body_entered(_body : Node2D) -> void:
    triggered.emit()
func _on_trigger_area_entered(_area : Area2D) -> void:
    triggered.emit()

func _on_triggered() -> void:
    if Global.camera_shaken_by_player.is_connected(trigger_if_near):
        Global.camera_shaken_by_player.disconnect(trigger_if_near)

    if !is_triggered:
        is_triggered = true
        cooldown_timer.start(randf_range(
            cooldown_min, cooldown_max
        ))

        if !manual_trigger:
            if $TriggerArea != null:
                $TriggerArea.queue_free()
        $GeneralArea.queue_free()

        if path != null:
            path.queue_free()
        if !stationary:
            $NavigationAgent2D/UpdatePlayerPos.start()

func _on_general_area_entered(area : Area2D) -> void:
    if area.name == &"PlayerGeneralArea":
        player_near = true
func _on_general_area_exited(area  : Area2D) -> void:
    if area.name == &"PlayerGeneralArea":
        player_near = false

var shielded := false

@onready var effect_dizzy_timer : Timer = $Effects/DizzyTimer
func effect_dizzy(power : float):
    rotate_weight = rotate_weight_init * randf_range(0.12, 0.21)
    speed = speed_init * randf_range(0.12, 0.21)

    effect_dizzy_timer.start(
        randf_range(1.5, 3.5) + remap(
            power, 50.0, 100.0, 2.0, 2.8
        )
    )
    await effect_dizzy_timer.timeout

    rotate_weight = rotate_weight_init
    speed = speed_init

@warning_ignore("unused_parameter")
func effect_knockback(power : float):
    move_and_collide(
        remap(power, 0.0, 100.0, 0.0, -40.0) * global_position\
        .direction_to(Global.player_physics_head.global_position)
    )

var lsight_coll := false
var lfire_coll := false
var lobst_coll := false
var on_line := false
var has_obstacle := false
