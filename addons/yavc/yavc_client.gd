@tool
class_name YavcClient
extends RefCounted
## TCP client for communicating with YAVC frontend server

signal connected
signal disconnected
signal lock_granted(path: String)
signal lock_denied(path: String, holder: String)
signal unlock_confirmed(path: String)
signal file_locked(path: String, holder: String)
signal file_unlocked(path: String)
signal error(message: String)

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7879

var _stream: StreamPeerTCP
var _connected := false
var _client_id: String = ""
var _pending_buffer: PackedByteArray = PackedByteArray()

func _init() -> void:
	_stream = StreamPeerTCP.new()
	_stream.set_big_endian(true)

func connect_to_server(host: String = DEFAULT_HOST, port: int = DEFAULT_PORT) -> Error:
	var err := _stream.connect_to_host(host, port)
	if err != OK:
		push_error("YAVC: Failed to connect to %s:%d - %s" % [host, port, error_string(err)])
		return err
	
	# Wait for connection (with timeout)
	var timeout := 5.0
	var elapsed := 0.0
	while _stream.get_status() == StreamPeerTCP.STATUS_CONNECTING and elapsed < timeout:
		_stream.poll()
		await Engine.get_main_loop().process_frame
		elapsed += Engine.get_main_loop().root.get_process_delta_time()
	
	if _stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		push_error("YAVC: Connection timeout or failed")
		return ERR_TIMEOUT
	
	_connected = true
	connected.emit()
	print("YAVC: Connected to frontend at %s:%d" % [host, port])
	return OK

func disconnect_from_server() -> void:
	if _connected:
		_send_message({"Disconnect": {}})
		_stream.disconnect_from_host()
		_connected = false
		_client_id = ""
		disconnected.emit()
		print("YAVC: Disconnected")

func is_connected_to_server() -> bool:
	if not _connected:
		return false
	_stream.poll()
	return _stream.get_status() == StreamPeerTCP.STATUS_CONNECTED

func register(name: String) -> Error:
	if not is_connected_to_server():
		return ERR_CONNECTION_ERROR
	
	var msg := {"Register": {"name": name}}
	var err := _send_message(msg)
	if err != OK:
		return err
	
	var response := await _read_message()
	if response == null:
		return ERR_PARSE_ERROR
	
	if response.has("Registered"):
		_client_id = response["Registered"]["client_id"]
		print("YAVC: Registered as %s (id: %s)" % [name, _client_id])
		return OK
	elif response.has("Error"):
		error.emit(response["Error"]["message"])
		return ERR_QUERY_FAILED
	
	return ERR_INVALID_DATA

func lock_file(path: String) -> Error:
	if not is_connected_to_server():
		return ERR_CONNECTION_ERROR
	
	var msg := {"LockRequest": {"path": path}}
	var err := _send_message(msg)
	if err != OK:
		return err
	
	var response := await _read_message()
	if response == null:
		return ERR_PARSE_ERROR
	
	if response.has("LockGranted"):
		lock_granted.emit(response["LockGranted"]["path"])
		return OK
	elif response.has("LockDenied"):
		lock_denied.emit(response["LockDenied"]["path"], response["LockDenied"]["holder"])
		return ERR_LOCKED
	elif response.has("Error"):
		error.emit(response["Error"]["message"])
		return ERR_QUERY_FAILED
	
	return ERR_INVALID_DATA

func unlock_file(path: String) -> Error:
	if not is_connected_to_server():
		return ERR_CONNECTION_ERROR
	
	var msg := {"UnlockRequest": {"path": path}}
	var err := _send_message(msg)
	if err != OK:
		return err
	
	var response := await _read_message()
	if response == null:
		return ERR_PARSE_ERROR
	
	if response.has("UnlockConfirmed"):
		unlock_confirmed.emit(response["UnlockConfirmed"]["path"])
		return OK
	elif response.has("Error"):
		error.emit(response["Error"]["message"])
		return ERR_QUERY_FAILED
	
	return ERR_INVALID_DATA

func query_file(path: String) -> Dictionary:
	if not is_connected_to_server():
		return {"error": "Not connected"}
	
	var msg := {"QueryFile": {"path": path}}
	var err := _send_message(msg)
	if err != OK:
		return {"error": "Send failed"}
	
	var response := await _read_message()
	if response == null:
		return {"error": "No response"}
	
	if response.has("FileState"):
		return response["FileState"]
	elif response.has("Error"):
		return {"error": response["Error"]["message"]}
	
	return {"error": "Invalid response"}

func list_locks() -> Array:
	if not is_connected_to_server():
		return []
	
	var msg := {"ListLocks": {}}
	var err := _send_message(msg)
	if err != OK:
		return []
	
	var response := await _read_message()
	if response == null:
		return []
	
	if response.has("LockList"):
		return response["LockList"]["locks"]
	
	return []

## Poll for push notifications (call this periodically)
func poll() -> void:
	if not is_connected_to_server():
		return
	
	_stream.poll()
	
	# Check if there's data available
	var available := _stream.get_available_bytes()
	if available == 0:
		return
	
	# Read all available data into buffer
	var data := _stream.get_data(available)
	if data[0] != OK:
		return
	_pending_buffer.append_array(data[1])
	
	# Process complete messages
	while _pending_buffer.size() >= 4:
		var length := (_pending_buffer[0] << 24) | (_pending_buffer[1] << 16) | (_pending_buffer[2] << 8) | _pending_buffer[3]
		
		if _pending_buffer.size() < 4 + length:
			break  # Wait for more data
		
		var json_bytes := _pending_buffer.slice(4, 4 + length)
		_pending_buffer = _pending_buffer.slice(4 + length)
		
		var json_str := json_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(json_str) != OK:
			push_error("YAVC: Failed to parse JSON: %s" % json_str)
			continue
		
		var msg: Dictionary = json.data
		_handle_push_notification(msg)

func _handle_push_notification(msg: Dictionary) -> void:
	if msg.has("FileLocked"):
		var path: String = msg["FileLocked"]["path"]
		var holder: String = msg["FileLocked"]["holder"]
		file_locked.emit(path, holder)
	elif msg.has("FileUnlocked"):
		var path: String = msg["FileUnlocked"]["path"]
		file_unlocked.emit(path)

func _send_message(msg: Dictionary) -> Error:
	var json_str: String = JSON.stringify(msg)
	var json_bytes: PackedByteArray = json_str.to_utf8_buffer()
	var length: int = json_bytes.size()
	
	# Write length prefix (4 bytes, big endian)
	_stream.put_32(length)
	
	# Write JSON payload
	var err: Error = _stream.put_data(json_bytes)
	if err != OK:
		push_error("YAVC: Failed to send JSON payload")
		return err
	
	return OK

func _read_message() -> Variant:
	# Read with timeout
	var timeout := 10.0
	var elapsed := 0.0
	
	# Wait for 4 bytes (length prefix)
	while _stream.get_available_bytes() < 4 and elapsed < timeout:
		_stream.poll()
		await Engine.get_main_loop().process_frame
		elapsed += Engine.get_main_loop().root.get_process_delta_time()
	
	if _stream.get_available_bytes() < 4:
		push_error("YAVC: Timeout waiting for response")
		return null
	
	# Read length
	var length := _stream.get_32()
	
	# Wait for payload
	elapsed = 0.0
	while _stream.get_available_bytes() < length and elapsed < timeout:
		_stream.poll()
		await Engine.get_main_loop().process_frame
		elapsed += Engine.get_main_loop().root.get_process_delta_time()
	
	if _stream.get_available_bytes() < length:
		push_error("YAVC: Timeout waiting for payload")
		return null
	
	var data := _stream.get_data(length)
	if data[0] != OK:
		push_error("YAVC: Failed to read payload")
		return null
	
	var payload_bytes: PackedByteArray = data[1]
	var json_str: String = payload_bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_error("YAVC: Failed to parse JSON: %s" % json_str)
		return null
	
	return json.data
