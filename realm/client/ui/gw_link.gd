class_name GwLink
extends Node
## The shell's TCP connection to the gateway: frames in and out, replies paired to requests by tag, pushes
## (town snapshots, chat, arrivals, an outing's result) as the `pushed` signal. Not a thread: `_process` reads
## whatever has arrived, so it must be in the tree. Use it with await:
##   var r: Dictionary = await link.call_req(GwWire.plain(GwWire.T_LIST_HEROES))
## A reply is a Dictionary with "t" (GwWire.R_*); R_ERR has "code" and "msg"; a lost connection or a reply that
## never comes (REPLY_TIMEOUT_S) answers R_LOST with "msg".
## Transport (docs/realm/wire.md, "Transport security"): TLS (StreamPeerTLS over the StreamPeerTCP), the gateway's
## certificate checked against Godot's trusted roots (TLSOptions.client() with no chain: the engine's CA bundle, or
## the project's network/tls/certificate_bundle_override) and the name connected to. Only a dev build
## (OS.is_debug_build) may trust one certificate file instead (`dev_cert`, the gateway's DB.dev-cert.pem) or speak
## plain TCP (`plain`, for a --dev-login gateway); a release build ignores both. A failed handshake is an error
## (`last_error`), never a retry in clear text.

signal pushed(msg: Dictionary)
signal lost(reason: String)

const REPLY_TIMEOUT_S: float = 30.0
const CONNECT_TIMEOUT_S: float = 8.0


class Pending extends RefCounted:
	signal done(reply: Dictionary)
	var at: float = 0.0
	var finished: bool = false

	func finish(r: Dictionary) -> void:
		if not finished:
			finished = true
			done.emit(r)


var _tcp: StreamPeerTCP = StreamPeerTCP.new()
## What frames are read from and written to: the TLS peer over `_tcp`, or `_tcp` itself when plain.
var _peer: StreamPeer = null
var _tls: StreamPeerTLS = null
## Dev builds only: speak plain TCP / trust this PEM certificate instead of the trusted roots.
var plain: bool = false
var dev_cert: String = ""
## Why the last `open` failed, for the shell to show ("" when it could not even reach the address).
var last_error: String = ""
var _buf: PackedByteArray = PackedByteArray()
var _tag: int = 0
var _pending: Dictionary = {}
var _now: float = 0.0
var host: String = ""
var port: int = 0
var connected: bool = false
## Counts, for the tests.
var frames_in: int = 0
var frames_out: int = 0


## Opens the connection and waits until it is up (or fails). True when connected; `last_error` says why not.
func open(h: String, p: int) -> bool:
	close()
	host = h
	port = p
	last_error = ""
	_tcp = StreamPeerTCP.new()
	_peer = _tcp
	_tls = null
	if _tcp.connect_to_host(h, p) != OK:
		return false
	var started: float = _now
	while true:
		_tcp.poll()
		var st: int = _tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			_tcp.set_no_delay(true)
			break
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE or _now - started > CONNECT_TIMEOUT_S:
			return false
		await get_tree().process_frame
	var dev: bool = OS.is_debug_build()
	if plain and dev:
		push_warning("GwLink: plain TCP to %s:%d: logins and chat are not encrypted (dev build, --plain)" % [h, p])
		connected = true
		return true
	var trusted: X509Certificate = null
	if dev and not dev_cert.is_empty():
		trusted = X509Certificate.new()
		if trusted.load(dev_cert) != OK:
			last_error = "cannot read the dev certificate %s" % dev_cert
			_tcp.disconnect_from_host()
			return false
	_tls = StreamPeerTLS.new()
	if _tls.connect_to_stream(_tcp, h, TLSOptions.client(trusted)) != OK:
		last_error = "secure connection to %s failed to start" % h
		_tcp.disconnect_from_host()
		return false
	while true:
		# The TCP peer is polled too, so a reset shows as an error here instead of a stall.
		_tcp.poll()
		_tls.poll()
		var st: int = _tls.get_status()
		if st == StreamPeerTLS.STATUS_CONNECTED:
			_peer = _tls
			connected = true
			return true
		if st == StreamPeerTLS.STATUS_ERROR_HOSTNAME_MISMATCH:
			last_error = "the gateway's certificate is not for %s" % h
			break
		if st == StreamPeerTLS.STATUS_ERROR or st == StreamPeerTLS.STATUS_DISCONNECTED:
			last_error = "secure connection to %s refused (its certificate is not trusted, or it does not speak TLS)" % h
			break
		if _now - started > CONNECT_TIMEOUT_S:
			last_error = "secure connection to %s timed out" % h
			break
		await get_tree().process_frame
	_tls.disconnect_from_stream()
	_tls = null
	_tcp.disconnect_from_host()
	return false


func close() -> void:
	if _tls != null:
		_tls.disconnect_from_stream()
		_tls = null
	if _tcp.get_status() != StreamPeerTCP.STATUS_NONE:
		_tcp.disconnect_from_host()
	_peer = _tcp
	connected = false
	_buf.clear()
	_fail_all("closed")


## True while the stream (TLS or plain) is up.
func _up() -> bool:
	if _tls != null:
		return _tls.get_status() == StreamPeerTLS.STATUS_CONNECTED
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func _fail_all(why: String) -> void:
	var all: Array = _pending.values()
	_pending.clear()
	for p in all:
		(p as Pending).finish({"t": GwWire.R_LOST, "msg": why})


## Sends a request ([type, body] from GwWire) and waits for its reply.
func call_req(req: Array) -> Dictionary:
	if not connected:
		return {"t": GwWire.R_LOST, "msg": "not connected"}
	_tag += 1
	var p := Pending.new()
	p.at = _now
	_pending[_tag] = p
	_send(int(req[0]), _tag, req[1])
	var r: Dictionary = await p.done
	return r


## A request nobody waits for (walking, pings). Its reply, if any, is dropped.
func send_only(req: Array) -> void:
	if connected:
		_tag += 1
		_send(int(req[0]), _tag, req[1])


func _send(t: int, tag: int, body: PackedByteArray) -> void:
	frames_out += 1
	_peer.put_data(GwWire.frame(t, tag, body))


func _process(delta: float) -> void:
	_now += delta
	if not connected:
		return
	_tcp.poll()
	if _tls != null:
		_tls.poll()
	if not _up():
		connected = false
		_fail_all("the gateway closed the connection")
		lost.emit("the gateway closed the connection")
		return
	var n: int = _peer.get_available_bytes()
	if n > 0:
		var got: Array = _peer.get_data(n)
		if int(got[0]) == OK:
			_buf.append_array(got[1] as PackedByteArray)
	_drain()
	for tag in _pending.keys():
		var p: Pending = _pending[tag]
		if _now - p.at > REPLY_TIMEOUT_S:
			_pending.erase(tag)
			p.finish({"t": GwWire.R_LOST, "msg": "no reply"})


func _drain() -> void:
	while _buf.size() >= 4:
		var len: int = _buf.decode_u32(0)
		if len < 5 or len > GwWire.FRAME_MAX:
			connected = false
			if _tls != null:
				_tls.disconnect_from_stream()
				_tls = null
			_tcp.disconnect_from_host()
			_fail_all("bad frame")
			lost.emit("bad frame")
			return
		if _buf.size() < 4 + len:
			return
		var t: int = _buf[4]
		var tag: int = _buf.decode_u32(5)
		var body: PackedByteArray = _buf.slice(9, 4 + len)
		_buf = _buf.slice(4 + len)
		frames_in += 1
		var r: Dictionary = GwWire.decode(t, body)
		if tag == 0:
			pushed.emit(r)
		elif _pending.has(tag):
			var p: Pending = _pending[tag]
			_pending.erase(tag)
			p.finish(r)
