extends Node
## Co-op networking over ENet (UDP).
##
## Model (built for low perceived latency):
## * Each player simulates their OWN heroine locally and instantly (client-side
##   prediction). Their state streams to everyone at 30 Hz on an unreliable channel.
## * The host is authoritative for enemies, damage to enemies, room flow and loot.
##   Enemy snapshots stream at 30 Hz; clients render them ~100 ms in the past with
##   interpolation, so motion stays smooth through jitter and packet loss.
## * Attacks show hit sparks and damage numbers immediately on the attacker's
##   screen (deterministic crits make the prediction match the host's result).
## * Damage TO a heroine is decided on her owner's device ("favor the defender"),
##   so a dodge that looked clean on your screen is always clean.

signal lobby_changed
signal connected_ok
signal connection_failed
signal disconnected
signal ping_updated(ms: int)

const PORT := 24680
const MAX_PLAYERS := 4

var online := false
var lobby: Array = [] ## [{peer, local_index, hero}]
var arena: Node = null
var ping_ms := 0
var _ping_timer := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected_ok.emit())
	multiplayer.connection_failed.connect(func():
		close()
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		close()
		disconnected.emit())

func is_host() -> bool:
	return not online or multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id() if online else 1

func host_game(hero: String) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	# Low-latency settings: no Nagle-like batching on ENet, compress small packets.
	p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = p
	online = true
	lobby = [{"peer": 1, "local_index": 0, "hero": hero, "weapon": Game.weapon_for(hero), "aspect": Game.run_aspect}]
	lobby_changed.emit()
	return OK

func join_game(ip: String, hero: String) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, PORT)
	if err != OK:
		return err
	p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = p
	online = true
	_join_hero = hero
	if not connected_ok.is_connected(_say_hello):
		connected_ok.connect(_say_hello)
	return OK

var _join_hero := "kaela"

func _say_hello() -> void:
	lobby_hello.rpc_id(1, _join_hero, Game.weapon_for(_join_hero), Game.run_aspect)

func close() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	lobby.clear()

func local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	lobby = lobby.filter(func(p): return p["peer"] != id)
	if is_host() and online:
		lobby_update.rpc(lobby)
	lobby_changed.emit()
	if arena:
		arena.on_peer_left(id)

func _process(delta: float) -> void:
	if online and not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 1.0
			ping.rpc_id(1, Time.get_ticks_msec())

# ---------------------------------------------------------------- lobby

@rpc("any_peer", "call_remote", "reliable")
func lobby_hello(hero: String, weapon: String, aspect: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if lobby.size() >= MAX_PLAYERS:
		return
	for p in lobby:
		if p["peer"] == id:
			return
	lobby.append({"peer": id, "local_index": 0, "hero": hero, "weapon": weapon, "aspect": aspect})
	lobby_update.rpc(lobby)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func lobby_update(l: Array) -> void:
	lobby = l
	lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func set_hero(hero: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	for p in lobby:
		if p["peer"] == id:
			p["hero"] = hero
	if multiplayer.is_server():
		lobby_update.rpc(lobby)
	lobby_changed.emit()

func change_my_hero(hero: String) -> void:
	for p in lobby:
		if p["peer"] == my_id():
			p["hero"] = hero
	if online:
		if multiplayer.is_server():
			lobby_update.rpc(lobby)
		else:
			set_hero.rpc_id(1, hero)
	lobby_changed.emit()
	if Game.run_weapon == "":
		change_my_loadout(Game.weapon_for(hero), 0) # default weapon follows the heroine

## Weapon + aspect for this device's heroine (picked before the run).
func change_my_loadout(weapon: String, aspect: int) -> void:
	for p in lobby:
		if p["peer"] == my_id():
			p["weapon"] = weapon
			p["aspect"] = aspect
	if online:
		if multiplayer.is_server():
			lobby_update.rpc(lobby)
		else:
			set_loadout.rpc_id(1, weapon, aspect)
	lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func set_loadout(weapon: String, aspect: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	for p in lobby:
		if p["peer"] == id:
			p["weapon"] = weapon
			p["aspect"] = aspect
	if multiplayer.is_server():
		lobby_update.rpc(lobby)
	lobby_changed.emit()

@rpc("authority", "call_local", "reliable")
func begin_run(seed_value: int, players: Array) -> void:
	Game.players = players
	Game.start_run(seed_value)
	get_tree().root.get_node("Main").start_arena()

@rpc("any_peer", "call_remote", "unreliable")
func ping(t: int) -> void:
	pong.rpc_id(multiplayer.get_remote_sender_id(), t)

@rpc("authority", "call_remote", "unreliable")
func pong(t: int) -> void:
	ping_ms = Time.get_ticks_msec() - t
	ping_updated.emit(ping_ms)

# ---------------------------------------------------------------- gameplay relay
# Channel 1 carries high-rate state so it never queues behind reliable events.

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func hero_state(key: String, s: Array) -> void:
	if arena: arena.net_hero_state(key, s)

@rpc("any_peer", "call_remote", "reliable")
func hero_action(key: String, action: String, pos: Vector2, dir: Vector2, seq: int, aim: Vector2) -> void:
	if arena: arena.net_hero_action(key, action, pos, dir, seq, aim)

@rpc("any_peer", "call_remote", "reliable")
func hero_boons(key: String, boons: Dictionary, max_hp: int) -> void:
	if arena: arena.net_hero_boons(key, boons, max_hp)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func world_snapshot(enemies: Array) -> void:
	if arena: arena.net_snapshot(enemies)

@rpc("authority", "call_remote", "reliable")
func world_event(kind: String, args: Array) -> void:
	if arena: arena.net_event(kind, args)

@rpc("any_peer", "call_remote", "reliable")
func projectile_consumed(id: int) -> void:
	if arena: arena.remove_projectile(id)

@rpc("any_peer", "call_remote", "reliable")
func request_door(door: int) -> void:
	if arena and multiplayer.is_server(): arena.try_advance(door)
