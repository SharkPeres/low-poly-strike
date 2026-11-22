extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GAME_PORT := 2456
const DISCOVERY_PORT := 2457
const MAX_PLAYERS := 4
const DISCOVERY_INTERVAL := 2.0

var players: Dictionary = {}
var player_profiles: Dictionary = {}
var status_label: Label
var address_input: LineEdit
var name_input: LineEdit
var room_name_input: LineEdit
var avatar_preview: TextureRect
var rooms_list: ItemList
var menu_layer: CanvasLayer
var menu_root: Control
var profile_panel: VBoxContainer
var rooms_panel: VBoxContainer
var connection_panel: VBoxContainer
var avatar_dialog: FileDialog
var selected_avatar_data := PackedByteArray()
var selected_avatar_path := ""
var discovery_socket := PacketPeerUDP.new()
var discovery_ready := false
var discovery_timer := 0.0
var is_hosting := false
var current_room_name := "Sala Low Poly"
var discovered_rooms: Dictionary = {}

func _ready() -> void:
    _build_arena()
    _setup_discovery()
    _build_menu()
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

func _build_arena() -> void:
    var ground := MeshInstance3D.new()
    var ground_mesh := BoxMesh.new()
    ground_mesh.size = Vector3(34, 1, 34)
    ground.mesh = ground_mesh
    ground.position.y = -0.5
    var ground_mat := StandardMaterial3D.new()
    ground_mat.albedo_color = Color("#6c9b62")
    ground.material_override = ground_mat
    add_child(ground)

    var floor_body := StaticBody3D.new()
    floor_body.position.y = -0.5
    var floor_collision := CollisionShape3D.new()
    var floor_shape := BoxShape3D.new()
    floor_shape.size = Vector3(34, 1, 34)
    floor_collision.shape = floor_shape
    floor_body.add_child(floor_collision)
    add_child(floor_body)

    var colors := [Color("#c58b52"), Color("#547da8"), Color("#b85d55"), Color("#d2b65b")]
    for i in range(12):
        var block := StaticBody3D.new()
        var mesh := MeshInstance3D.new()
        var box := BoxMesh.new()
        box.size = Vector3(2.5, 1.4, 2.5)
        mesh.mesh = box
        var mat := StandardMaterial3D.new()
        mat.albedo_color = colors[i % colors.size()]
        mesh.material_override = mat
        block.add_child(mesh)
        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = box.size
        col.shape = shape
        block.add_child(col)
        var angle := TAU * float(i) / 12.0
        block.position = Vector3(cos(angle) * 9.0, 0.7, sin(angle) * 9.0)
        add_child(block)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -25, 0)
    light.shadow_enabled = true
    add_child(light)
    var env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_SKY
    environment.sky = Sky.new()
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#a9c5df")
    environment.ambient_light_energy = 0.7
    env.environment = environment
    add_child(env)

func _setup_discovery() -> void:
    var err := discovery_socket.bind(DISCOVERY_PORT, "*", 1)
    if err == OK:
        discovery_socket.set_broadcast_enabled(true)
        discovery_ready = true

func _build_menu() -> void:
    menu_layer = CanvasLayer.new()
    add_child(menu_layer)
    menu_root = Control.new()
    menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_layer.add_child(menu_root)

    var shade := ColorRect.new()
    shade.color = Color(0.035, 0.055, 0.075, 0.94)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_root.add_child(shade)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_root.add_child(center)
    var main_panel := PanelContainer.new()
    main_panel.custom_minimum_size = Vector2(680, 500)
    center.add_child(main_panel)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 12)
    main_panel.add_child(outer)

    var title := Label.new()
    title.text = "LOW POLY STRIKE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    outer.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "FPS MULTIPLAYER • P2P • ATÉ 4 JOGADORES"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_color_override("font_color", Color("#a9c5df"))
    outer.add_child(subtitle)

    var tabs := HBoxContainer.new()
    outer.add_child(tabs)
    var profile_tab := Button.new()
    profile_tab.text = "Meu perfil"
    profile_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    profile_tab.pressed.connect(func(): _show_menu_panel("profile"))
    tabs.add_child(profile_tab)
    var rooms_tab := Button.new()
    rooms_tab.text = "Lista de salas"
    rooms_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rooms_tab.pressed.connect(func(): _show_menu_panel("rooms"))
    tabs.add_child(rooms_tab)
    var connect_tab := Button.new()
    connect_tab.text = "Entrar por IP"
    connect_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    connect_tab.pressed.connect(func(): _show_menu_panel("connection"))
    tabs.add_child(connect_tab)

    profile_panel = VBoxContainer.new()
    outer.add_child(profile_panel)
    var profile_title := Label.new()
    profile_title.text = "IDENTIDADE DO JOGADOR"
    profile_title.add_theme_font_size_override("font_size", 20)
    profile_panel.add_child(profile_title)
    var profile_row := HBoxContainer.new()
    profile_panel.add_child(profile_row)
    avatar_preview = TextureRect.new()
    avatar_preview.custom_minimum_size = Vector2(96, 96)
    avatar_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    profile_row.add_child(avatar_preview)
    var profile_fields := VBoxContainer.new()
    profile_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    profile_row.add_child(profile_fields)
    name_input = LineEdit.new()
    name_input.placeholder_text = "Digite seu nome no jogo"
    name_input.text = "Jogador"
    profile_fields.add_child(name_input)
    var choose_avatar := Button.new()
    choose_avatar.text = "Escolher foto do computador"
    choose_avatar.pressed.connect(_open_avatar_dialog)
    profile_fields.add_child(choose_avatar)
    var photo_note := Label.new()
    photo_note.text = "Foto opcional • PNG/JPG • exibida no perfil e enviada aos jogadores"
    photo_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    photo_note.add_theme_font_size_override("font_size", 12)
    profile_fields.add_child(photo_note)

    rooms_panel = VBoxContainer.new()
    outer.add_child(rooms_panel)
    var rooms_title := Label.new()
    rooms_title.text = "SALAS NA REDE LOCAL"
    rooms_title.add_theme_font_size_override("font_size", 20)
    rooms_panel.add_child(rooms_title)
    var room_buttons := HBoxContainer.new()
    rooms_panel.add_child(room_buttons)
    room_name_input = LineEdit.new()
    room_name_input.text = "Sala do jogador"
    room_name_input.placeholder_text = "Nome da sala que você vai criar"
    room_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    room_buttons.add_child(room_name_input)
    var host_button := Button.new()
    host_button.text = "Criar sala"
    host_button.pressed.connect(_host_game)
    room_buttons.add_child(host_button)
    var refresh_button := Button.new()
    refresh_button.text = "Atualizar"
    refresh_button.pressed.connect(_refresh_rooms)
    rooms_panel.add_child(refresh_button)
    rooms_list = ItemList.new()
    rooms_list.custom_minimum_size = Vector2(0, 150)
    rooms_list.item_selected.connect(_on_room_selected)
    rooms_panel.add_child(rooms_list)
    var join_room_button := Button.new()
    join_room_button.text = "Entrar na sala selecionada"
    join_room_button.pressed.connect(_join_selected_room)
    rooms_panel.add_child(join_room_button)

    connection_panel = VBoxContainer.new()
    outer.add_child(connection_panel)
    var connection_title := Label.new()
    connection_title.text = "CONEXÃO DIRETA"
    connection_title.add_theme_font_size_override("font_size", 20)
    connection_panel.add_child(connection_title)
    address_input = LineEdit.new()
    address_input.placeholder_text = "IP do anfitrião (ex.: 192.168.0.10)"
    address_input.text = "127.0.0.1"
    connection_panel.add_child(address_input)
    var join_button := Button.new()
    join_button.text = "Conectar por IP"
    join_button.pressed.connect(_join_game)
    connection_panel.add_child(join_button)

    status_label = Label.new()
    status_label.text = "Defina seu perfil e crie uma sala ou escolha uma sala encontrada."
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.add_theme_color_override("font_color", Color("#f2d38a"))
    outer.add_child(status_label)

    avatar_dialog = FileDialog.new()
    avatar_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    avatar_dialog.access = FileDialog.ACCESS_FILESYSTEM
    avatar_dialog.add_filter("*.png, *.jpg, *.jpeg", "Imagens PNG/JPG")
    avatar_dialog.file_selected.connect(_on_avatar_selected)
    menu_root.add_child(avatar_dialog)
    _show_menu_panel("profile")

func _show_menu_panel(which: String) -> void:
    profile_panel.visible = which == "profile"
    rooms_panel.visible = which == "rooms"
    connection_panel.visible = which == "connection"
    if which == "rooms":
        _refresh_rooms()

func _open_avatar_dialog() -> void:
    avatar_dialog.popup_centered(Vector2i(760, 520))

func _on_avatar_selected(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        status_label.text = "Não foi possível abrir essa imagem."
        return
    selected_avatar_path = path
    var image := Image.new()
    var err := image.load(path)
    if err != OK:
        status_label.text = "Formato de imagem não reconhecido. Use PNG ou JPG."
        selected_avatar_data = PackedByteArray()
        return
    image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
    selected_avatar_data = image.save_png_to_buffer()
    avatar_preview.texture = ImageTexture.create_from_image(image)
    status_label.text = "Foto selecionada e otimizada para enviar aos outros jogadores."

func _get_player_name() -> String:
    var value := name_input.text.strip_edges()
    if value.is_empty():
        return "Jogador"
    return value.left(20)

func _host_game() -> void:
    if not _profile_valid():
        return
    var peer := ENetMultiplayerPeer.new()
    var error := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
    if error != OK:
        status_label.text = "Falha ao criar sala: " + error_string(error)
        return
    multiplayer.multiplayer_peer = peer
    is_hosting = true
    current_room_name = room_name_input.text.strip_edges()
    if current_room_name.is_empty():
        current_room_name = "Sala de " + _get_player_name()
    _spawn_player(1, _get_player_name(), selected_avatar_data, Vector3(-5, 0.1, 5))
    menu_root.visible = false
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    status_label.text = "Sala criada. Aguardando jogadores..."

func _profile_valid() -> bool:
    if _get_player_name().is_empty():
        status_label.text = "Digite um nome antes de continuar."
        _show_menu_panel("profile")
        return false
    return true

func _join_game() -> void:
    if not _profile_valid():
        return
    var ip := address_input.text.strip_edges()
    if ip.is_empty():
        status_label.text = "Digite o IP do anfitrião."
        return
    _connect_to_ip(ip)

func _connect_to_ip(ip: String) -> void:
    var peer := ENetMultiplayerPeer.new()
    var error := peer.create_client(ip, GAME_PORT)
    if error != OK:
        status_label.text = "Falha ao iniciar conexão: " + error_string(error)
        return
    multiplayer.multiplayer_peer = peer
    status_label.text = "Conectando a " + ip + "..."

func _on_connected() -> void:
    status_label.text = "Conectado! Entrando na sala..."
    _request_join.rpc_id(1, _get_player_name(), selected_avatar_data)

@rpc("any_peer", "reliable")
func _request_join(player_name: String, avatar_data: PackedByteArray) -> void:
    if not multiplayer.is_server():
        return
    var sender := multiplayer.get_remote_sender_id()
    if players.size() >= MAX_PLAYERS or players.has(sender):
        return
    for existing_id in players.keys():
        var p = player_profiles[int(existing_id)]
        _receive_spawn.rpc_id(sender, int(existing_id), str(p.name), p.avatar, players[int(existing_id)].global_position)
    var spawn_position := Vector3(-5.0 + float(players.size()) * 3.0, 0.1, 5.0)
    _spawn_player(sender, player_name, avatar_data, spawn_position)
    _receive_spawn.rpc(sender, player_name, avatar_data, spawn_position)

@rpc("authority", "reliable")
func _receive_spawn(peer_id: int, player_name: String, avatar_data: PackedByteArray, spawn_position: Vector3) -> void:
    if players.has(peer_id):
        return
    _spawn_player(peer_id, player_name, avatar_data, spawn_position)

func _spawn_player(peer_id: int, player_name: String, avatar_data: PackedByteArray, spawn_position: Vector3) -> void:
    if players.has(peer_id):
        return
    var player = PLAYER_SCENE.instantiate()
    player.name = str(peer_id)
    player.set_multiplayer_authority(peer_id)
    add_child(player)
    player.global_position = spawn_position
    player.setup_profile(player_name, avatar_data)
    players[peer_id] = player
    player_profiles[peer_id] = {"name": player_name, "avatar": avatar_data}

func _on_peer_connected(_id: int) -> void:
    pass

func _on_peer_disconnected(id: int) -> void:
    if players.has(id):
        players[id].queue_free()
        players.erase(id)
        player_profiles.erase(id)

func _on_connection_failed() -> void:
    status_label.text = "Não conectou. Confira IP, porta e firewall."

func _on_server_disconnected() -> void:
    status_label.text = "O anfitrião encerrou a sala."
    menu_root.visible = true
    is_hosting = false

func _process(delta: float) -> void:
    if Input.is_action_just_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
            menu_root.visible = true
    if discovery_ready:
        _poll_discovery()
        discovery_timer += delta
        if discovery_timer >= DISCOVERY_INTERVAL:
            discovery_timer = 0.0
            if is_hosting:
                _broadcast_room()

func _broadcast_room() -> void:
    if not discovery_ready:
        return
    var packet := JSON.stringify({"kind": "room", "name": current_room_name, "ip": _get_local_lan_ip(), "port": GAME_PORT, "players": players.size(), "max": MAX_PLAYERS})
    discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
    discovery_socket.put_packet(packet.to_utf8_buffer())

func _poll_discovery() -> void:
    while discovery_socket.get_available_packet_count() > 0:
        var packet := discovery_socket.get_packet().get_string_from_utf8()
        var parsed = JSON.parse_string(packet)
        if typeof(parsed) != TYPE_DICTIONARY:
            continue
        if parsed.get("kind", "") == "discover":
            if is_hosting:
                _broadcast_room()
            continue
        if parsed.get("kind", "") != "room":
            continue
        var ip := str(parsed.get("ip", discovery_socket.get_packet_ip()))
        if ip == _get_local_lan_ip():
            continue
        var key := ip + ":" + str(parsed.get("port", GAME_PORT))
        discovered_rooms[key] = {"name": str(parsed.get("name", "Sala")), "ip": ip, "players": int(parsed.get("players", 1)), "max": int(parsed.get("max", MAX_PLAYERS)), "seen": Time.get_ticks_msec()}
    var now := Time.get_ticks_msec()
    for key in discovered_rooms.keys():
        if now - int(discovered_rooms[key].seen) > 7000:
            discovered_rooms.erase(key)
    if is_instance_valid(rooms_list) and rooms_panel.visible:
        _populate_rooms_list()

func _get_local_lan_ip() -> String:
    for address in IP.get_local_addresses():
        if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
            return address
    return "127.0.0.1"

func _refresh_rooms() -> void:
    if not discovery_ready:
        status_label.text = "Descoberta de salas indisponível nesta rede. Use Entrar por IP."
        return
    if is_hosting:
        _broadcast_room()
    else:
        _send_discovery_ping()
    _populate_rooms_list()

func _send_discovery_ping() -> void:
    discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
    discovery_socket.put_packet("{\"kind\":\"discover\"}".to_utf8_buffer())

func _populate_rooms_list() -> void:
    rooms_list.clear()
    for key in discovered_rooms.keys():
        var room: Dictionary = discovered_rooms[key]
        rooms_list.add_item("%s  |  %d/%d jogadores  |  %s" % [room.name, room.players, room.max, room.ip])
        rooms_list.set_item_metadata(rooms_list.item_count - 1, key)
    if rooms_list.item_count == 0:
        rooms_list.add_item("Nenhuma sala encontrada na rede local. Atualize ou entre por IP.")
        rooms_list.set_item_disabled(0, true)

func _on_room_selected(index: int) -> void:
    if rooms_list.is_item_disabled(index):
        return
    var key := str(rooms_list.get_item_metadata(index))
    if discovered_rooms.has(key):
        address_input.text = str(discovered_rooms[key].ip)

func _join_selected_room() -> void:
    if rooms_list.get_selected_items().is_empty():
        status_label.text = "Selecione uma sala da lista primeiro."
        return
    var index := rooms_list.get_selected_items()[0]
    if rooms_list.is_item_disabled(index):
        return
    var key := str(rooms_list.get_item_metadata(index))
    if not discovered_rooms.has(key):
        status_label.text = "Essa sala não está mais anunciando. Atualize a lista."
        return
    _show_menu_panel("connection")
    address_input.text = str(discovered_rooms[key].ip)
    _join_game()
