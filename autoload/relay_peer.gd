extends MultiplayerPeerExtension
## Online co-op through the Veilborne relay (tools/cloudflare/relay.js), over one
## WebSocket per phone. Plugs into Godot's high-level multiplayer exactly like
## ENet does (host = peer 1, friends talk to the host, SceneMultiplayer relays
## friend<->friend), so the rest of the game's networking is unchanged.
##
## Built for phones: when the app goes to the background (e.g. to send the
## invite on WhatsApp) Net calls app_paused(), the room is told we are away and
## keeps our place; app_resumed() (or any dropped connection) reconnects with
## our token and the game never sees a disconnect. Reliable packets sent while
## the link is down are kept and sent after reconnecting; the relay does the same
## the other way. Only an explicit leave, a closed room or 10 minutes without a
## connection end the session.

signal relay_event(kind: String) ## "host_away", "host_back", "reconnecting", "reconnected"

const GIVE_UP_MS := 10 * 60 * 1000
const FLAG_RELIABLE := 1

var server := ""      ## wss://host (no trailing slash)
var code := ""
var hosting := false
var my_id := 0
var token := ""
var error_code := ""  ## set when the relay refused us ("taken", "no_room", "full", ...)

var _ws: WebSocketPeer
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _welcomed := false
var _in: Array = []          ## [[from, PackedByteArray, mode, channel]]
var _out: Array = []         ## framed reliable packets waiting for a connection
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _retry_at := 0
var _retry_delay := 250
var _down_since := 0
var _paused := false
var _closing := false
var _nodelay_set := false
var _friends := {}           ## host: id -> true

func start(p_server: String, p_code: String, p_host: bool, p_token := "") -> void:
	server = p_server.trim_suffix("/")
	code = p_code
	hosting = p_host
	token = p_token
	my_id = 1 if hosting else 0
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	_open()

func _url() -> String:
	var q := "role=%s" % ("host" if hosting else "join")
	if token != "":
		q += "&token=" + token
	if not hosting and my_id > 1:
		q += "&id=%d" % my_id
	return "%s/room/%s?%s" % [server, code, q]

func _open() -> void:
	_nodelay_set = false
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 22
	_ws.outbound_buffer_size = 1 << 22
	_ws.max_queued_packets = 8192
	if _ws.connect_to_url(_url()) != OK:
		_ws = null
		_schedule_retry()

func _schedule_retry() -> void:
	if _down_since == 0:
		_down_since = Time.get_ticks_msec()
		if _welcomed:
			relay_event.emit("reconnecting")
	_retry_at = Time.get_ticks_msec() + _retry_delay
	_retry_delay = mini(_retry_delay * 2, 3000)

## The app is going to the background: tell the room we are away, then let go.
func app_paused() -> void:
	_paused = true
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "away"}))
		_ws.poll()
		_ws.close(1000, "away")
	_ws = null

## Back from the background: reconnect at once.
func app_resumed() -> void:
	_paused = false
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED or _closing:
		return
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_retry_delay = 250
		_ws = null
		_open()

func is_reconnecting() -> bool:
	return _welcomed and _down_since != 0

# ---------------------------------------------------------------- MultiplayerPeer

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED or _paused:
		return
	if _ws == null:
		if Time.get_ticks_msec() >= _retry_at:
			_open()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _nodelay_set:
			_nodelay_set = true
			_ws.set_no_delay(true) # small game packets go out at once
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_control(pkt.get_string_from_utf8())
			else:
				_data(pkt)
	elif st == WebSocketPeer.STATE_CLOSED:
		_ws = null
		if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
		if error_code != "" or _closing:
			_end()
			return
		if not _welcomed and Time.get_ticks_msec() - (_down_since if _down_since else Time.get_ticks_msec()) > 15000:
			error_code = "unreachable"
			_end()
			return
		_schedule_retry()
	if _down_since != 0 and _welcomed and Time.get_ticks_msec() - _down_since > GIVE_UP_MS:
		_end()

func _control(s: String) -> void:
	var m = JSON.parse_string(s)
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"welcome":
			my_id = int(m.get("id", my_id))
			token = str(m.get("token", token))
			_retry_delay = 250
			var was_down := _down_since != 0
			_down_since = 0
			for b in _out:
				_ws.send(b)
			_out.clear()
			if not _welcomed:
				_welcomed = true
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				if hosting:
					for id in m.get("peers", []):
						_add_friend(int(id))
				else:
					peer_connected.emit(1)
			elif was_down:
				relay_event.emit("reconnected")
		"join":
			if hosting:
				_add_friend(int(m["id"]))
		"leave":
			if hosting and _friends.has(int(m["id"])):
				_friends.erase(int(m["id"]))
				peer_disconnected.emit(int(m["id"]))
		"host_away", "host_back":
			relay_event.emit(str(m["t"]))
		"error":
			error_code = str(m.get("code", "error"))
		"closed":
			_closing = true
			_end()

func _add_friend(id: int) -> void:
	if not _friends.has(id):
		_friends[id] = true
		peer_connected.emit(id)

func _data(pkt: PackedByteArray) -> void:
	if pkt.size() < 1:
		return
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if (pkt[0] & FLAG_RELIABLE) else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var ch := pkt[0] >> 1
	if hosting:
		if pkt.size() < 5:
			return
		_in.append([pkt.decode_s32(1), pkt.slice(5), mode, ch])
	else:
		_in.append([1, pkt.slice(1), mode, ch])

func _end() -> void:
	if _ws:
		_ws.close()
		_ws = null
	var was := _status
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	if was != MultiplayerPeer.CONNECTION_DISCONNECTED and _welcomed:
		if hosting:
			for id in _friends.keys():
				peer_disconnected.emit(id)
		else:
			peer_disconnected.emit(1)
	_friends.clear()

func _get_available_packet_count() -> int:
	return _in.size()

func _get_packet_script() -> PackedByteArray:
	if _in.is_empty():
		return PackedByteArray()
	return _in.pop_front()[1]

func _get_packet_peer() -> int:
	return _in[0][0] if not _in.is_empty() else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _in[0][2] if not _in.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE

func _get_packet_channel() -> int:
	return _in[0][3] if not _in.is_empty() else 0

func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var reliable := _mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var flags := (FLAG_RELIABLE if reliable else 0) | (mini(_channel, 63) << 1)
	var head := PackedByteArray([flags])
	if hosting:
		head.resize(5)
		head.encode_s32(1, _target)
	var b := head + p_buffer
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _down_since == 0:
		return _ws.send(b)
	if reliable:
		_out.append(b)
	return OK

func _get_max_packet_size() -> int:
	return 1 << 20

func _set_target_peer(p_peer: int) -> void:
	_target = p_peer

func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_mode = p_mode

func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode

func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel

func _get_transfer_channel() -> int:
	return _channel

func _is_server() -> bool:
	return hosting

func _is_server_relay_supported() -> bool:
	return true

func _get_unique_id() -> int:
	return my_id if my_id > 0 else 1

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status

func _close() -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "bye"}))
		_ws.poll()
	_closing = true
	_end()

func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if hosting and _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "kick", "id": p_peer}))
	if _friends.has(p_peer):
		_friends.erase(p_peer)
		peer_disconnected.emit(p_peer)

func _set_refuse_new_connections(_p_enable: bool) -> void:
	pass

func _is_refusing_new_connections() -> bool:
	return false
