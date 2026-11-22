extends CharacterBody3D

const SPEED := 7.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.0022
const FIRE_RATE := 0.22

var health := 100
var pitch := 0.0
var fire_cooldown := 0.0
var sync_timer := 0.0
var body_material: StandardMaterial3D
var display_name := "Jogador"
var avatar_texture: Texture2D
var name_tag: Label3D
var avatar_sprite: Sprite3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/RayCast3D
@onready var body_mesh: MeshInstance3D = $BodyMesh

func _ready() -> void:
    body_material = StandardMaterial3D.new()
    body_material.albedo_color = Color("#4c9ed9") if get_multiplayer_authority() % 2 == 1 else Color("#d9784c")
    body_mesh.material_override = body_material
    name_tag = Label3D.new()
    name_tag.position = Vector3(0, 2.25, 0)
    name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    name_tag.font_size = 32
    name_tag.outline_size = 8
    name_tag.text = display_name
    add_child(name_tag)
    avatar_sprite = Sprite3D.new()
    avatar_sprite.position = Vector3(0, 2.85, 0)
    avatar_sprite.pixel_size = 0.006
    avatar_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(avatar_sprite)
    if is_multiplayer_authority():
        camera.current = true
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    else:
        camera.current = false

func setup_profile(player_name: String, avatar_data: PackedByteArray) -> void:
    display_name = player_name
    if is_instance_valid(name_tag):
        name_tag.text = display_name
    if avatar_data.is_empty():
        return
    var image := Image.new()
    var err := image.load_png_from_buffer(avatar_data)
    if err != OK:
        err = image.load_jpg_from_buffer(avatar_data)
    if err == OK:
        avatar_texture = ImageTexture.create_from_image(image)
        if is_instance_valid(avatar_sprite):
            avatar_sprite.texture = avatar_texture
            avatar_sprite.visible = true

func _unhandled_input(event: InputEvent) -> void:
    if not is_multiplayer_authority():
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        pitch = clamp(pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-85), deg_to_rad(85))
        head.rotation.x = pitch
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        _shoot()

func _physics_process(delta: float) -> void:
    if not is_multiplayer_authority():
        return
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    if not is_on_floor():
        velocity += get_gravity() * delta
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = JUMP_VELOCITY
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction:
        velocity.x = direction.x * SPEED
        velocity.z = direction.z * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)
        velocity.z = move_toward(velocity.z, 0, SPEED)
    move_and_slide()
    sync_timer += delta
    if sync_timer >= 0.05:
        sync_timer = 0.0
        _sync_state.rpc(global_position, rotation.y, pitch)

func _shoot() -> void:
    if fire_cooldown > 0.0:
        return
    fire_cooldown = FIRE_RATE
    ray.force_raycast_update()
    if ray.is_colliding():
        var target = ray.get_collider()
        if target is CharacterBody3D and target != self:
            _request_damage.rpc_id(1, str(target.name), 25)
    _show_muzzle_flash.rpc()

@rpc("any_peer", "unreliable")
func _sync_state(pos: Vector3, yaw: float, camera_pitch: float) -> void:
    if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
        return
    if is_multiplayer_authority():
        return
    global_position = pos
    rotation.y = yaw
    head.rotation.x = camera_pitch

@rpc("any_peer", "reliable")
func _request_damage(target_name: String, amount: int) -> void:
    if not multiplayer.is_server():
        return
    var sender := multiplayer.get_remote_sender_id()
    var main := get_parent()
    if not main.players.has(sender) or not main.players.has(int(target_name)):
        return
    var target = main.players[int(target_name)]
    target._apply_damage.rpc(amount)

@rpc("any_peer", "reliable", "call_local")
func _apply_damage(amount: int) -> void:
    var sender := multiplayer.get_remote_sender_id()
    if sender != 0 and sender != 1:
        return
    health = maxi(0, health - amount)
    if health == 0:
        health = 100
        global_position = Vector3(randf_range(-6, 6), 0.1, randf_range(-6, 6))

@rpc("authority", "unreliable", "call_local")
func _show_muzzle_flash() -> void:
    body_mesh.scale = Vector3(1.08, 1.02, 1.08)
    await get_tree().create_timer(0.06).timeout
    if is_instance_valid(body_mesh):
        body_mesh.scale = Vector3.ONE
