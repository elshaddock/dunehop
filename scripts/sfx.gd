extends Node

## Placeholder audio, synthesised at boot.
##
## The art is primitives, so the sound is oscillators. Every effect below is a handful of
## numbers instead of a wav file, which keeps the repo text-only, makes retuning a sound a diff
## you can actually read, and means there is no import step to go stale. When real recordings
## arrive, replace the table in `_build()` and every call site stays as it is.
##
## Everything is deterministic: the noise generators are seeded, so a given build always sounds
## the same rather than rerolling its own foley on every launch.

const RATE := 22050
## Enough voices that a landing, a pickup and a pod burst in the same frame all speak.
const VOICES := 8

enum Wave { SINE, TRI, SQUARE, SAW }

## Quietest and loudest the parasail wind gets, in dB.
const WIND_QUIET := -34.0
const WIND_LOUD := -11.0
## dB per second the wind is allowed to move, so gusts fade rather than snap.
const WIND_SLEW := 190.0

var _bank := {}
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
var _next_flat := 0
var _next_spatial := 0
var _wind: AudioStreamPlayer = null
var _wind_target := 0.0
var _silent := false


func _ready() -> void:
	_build()

	# Headless runs get the Dummy audio driver, where mixing is pure cost and the server never
	# hands its playbacks back at exit, so a clean test run reports leaked instances for sounds
	# nobody heard. The bank is still built either way, since a missing or empty sound is
	# exactly the sort of thing the harness should catch.
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		set_process(false)
		return

	for i in VOICES:
		var flat := AudioStreamPlayer.new()
		add_child(flat)
		_flat.append(flat)

		var spatial := AudioStreamPlayer3D.new()
		spatial.unit_size = 14.0
		spatial.max_distance = 70.0
		add_child(spatial)
		_spatial.append(spatial)

	_wind = AudioStreamPlayer.new()
	_wind.stream = _bank["wind"]
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()


func _process(delta: float) -> void:
	var goal := -80.0 if _wind_target <= 0.01 else lerpf(WIND_QUIET, WIND_LOUD, _wind_target)
	_wind.volume_db = move_toward(_wind.volume_db, goal, WIND_SLEW * delta)
	_wind.pitch_scale = lerpf(0.85, 1.28, _wind_target)


## Shutting down mid-note leaves the audio server holding a playback, and a held playback holds
## the stream that fed it, so quitting during the wind loop reports leaked instances. Handing
## the voices back first is also what stops the glide from droning on across a scene change.
func _exit_tree() -> void:
	silence()
	for voice in _flat:
		voice.stream = null
	for voice in _spatial:
		voice.stream = null
	if _wind != null:
		_wind.stream = null
	_bank.clear()


## Cut everything that is currently sounding.
func silence() -> void:
	_wind_target = 0.0
	if _wind != null:
		_wind.stop()
	for voice in _flat:
		voice.stop()
	for voice in _spatial:
		voice.stop()


# --- playback ---------------------------------------------------------------


## Fire a one-shot with no position. Most sounds are the player's own body, and those want to
## sit at a fixed place in the mix rather than pan around as the camera orbits.
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream: AudioStreamWAV = _bank.get(name)
	if stream == null:
		push_warning("no such sound: %s" % name)
		return
	if _silent:
		return
	var voice := _flat_voice()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()


## Fire a one-shot out in the world, for things that happen away from the player: a seed
## landing, a pod bursting, a slab rattling across the plaza.
func play_at(name: String, where: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var stream: AudioStreamWAV = _bank.get(name)
	if stream == null:
		push_warning("no such sound: %s" % name)
		return
	if _silent:
		return
	var voice := _spatial_voice()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.global_position = where
	voice.play()


## How hard the parasail wind blows, 0 for silence. Held rather than triggered, since the glide
## is a state and not an event.
func set_wind(amount: float) -> void:
	_wind_target = clampf(amount, 0.0, 1.0)


func has(name: String) -> bool:
	return _bank.has(name)


func names() -> Array:
	return _bank.keys()


func stream(name: String) -> AudioStreamWAV:
	return _bank.get(name)


## An idle voice if there is one, otherwise steal the one that has been going longest. The
## round-robin cursor only moves when a voice is actually stolen, so stealing walks the pool
## instead of hammering whichever slot the counter happens to be sitting on.
func _flat_voice() -> AudioStreamPlayer:
	for voice in _flat:
		if not voice.playing:
			return voice
	var stolen := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	return stolen


func _spatial_voice() -> AudioStreamPlayer3D:
	for voice in _spatial:
		if not voice.playing:
			return voice
	var stolen := _spatial[_next_spatial]
	_next_spatial = (_next_spatial + 1) % _spatial.size()
	return stolen


# --- the table --------------------------------------------------------------


func _build() -> void:
	# Springy launch: a fast rise is what sells the stored charge letting go.
	_bank["leap"] = _wav(_norm(_mix(
		_tone(0.22, 180.0, 540.0, 10.0, Wave.TRI, 0.55),
		_noise(0.06, 44.0, 2400.0, false, 101), 0.0, 0.55
	)))

	# Body meeting sand: a low thump under a soft, dull scuff.
	_bank["land"] = _wav(_norm(_mix(
		_noise(0.20, 22.0, 620.0, false, 102),
		_tone(0.14, 105.0, 62.0, 26.0), 0.0, 0.9
	)))

	# Stance swap has to be crisp and cheap: you hear it many times a minute.
	_bank["swap"] = _wav(_norm(_mix(
		_noise(0.05, 70.0, 3400.0, true, 103),
		_tone(0.05, 520.0, 380.0, 46.0, Wave.TRI), 0.0, 0.7
	)))

	# The footdrum. Long, low and heavy, since it is the one move with a radius.
	var drum := _tone(0.62, 78.0, 34.0, 6.5)
	drum = _mix(drum, _tone(0.30, 152.0, 70.0, 14.0, Wave.TRI), 0.0, 0.4)
	drum = _mix(drum, _noise(0.09, 34.0, 1600.0, false, 104), 0.0, 0.7)
	_bank["drum"] = _wav(_norm(drum))

	# Stone giving way: a bright snap, then rubble tumbling after it.
	var breaks := _noise(0.10, 32.0, 5000.0, true, 105)
	breaks = _mix(breaks, _noise(0.55, 7.0, 2200.0, false, 106), 0.02, 0.85)
	breaks = _mix(breaks, _tone(0.34, 260.0, 84.0, 10.0, Wave.SAW), 0.0, 0.35)
	_bank["slab_break"] = _wav(_norm(breaks))

	# A near-miss drum. Dry, buzzing, unresolved: the sound of something loose that did not
	# quite come free, which is exactly the hint being given.
	_bank["slab_rattle"] = _wav(_norm(_mix(
		_am(_noise(0.28, 13.0, 1500.0, false, 107), 38.0, 0.85),
		_tone(0.22, 132.0, 118.0, 16.0, Wave.TRI), 0.0, 0.45
	)))

	# Held while gliding, so it must loop without a seam. Slow swell keeps it from droning.
	_bank["wind"] = _wav(_loop(_norm(_am(
		_noise(1.60, 0.0, 780.0, false, 108), 0.7, 0.5
	))), true)

	_bank["spit"] = _wav(_norm(_mix(
		_noise(0.09, 46.0, 4200.0, true, 109),
		_tone(0.07, 760.0, 280.0, 40.0, Wave.TRI), 0.0, 0.5
	)))

	_bank["shot_hit"] = _wav(_norm(_noise(0.08, 52.0, 2400.0, false, 110)))

	# Pod popping open, then seeds scattering out of it.
	var pod := _tone(0.10, 300.0, 130.0, 30.0, Wave.SQUARE)
	pod = _mix(pod, _noise(0.34, 11.0, 3000.0, true, 111), 0.03, 0.8)
	_bank["pod_burst"] = _wav(_norm(pod))

	# Bright and short. The caller raises the pitch as the pouch fills, so a run of pickups
	# climbs and you can hear how close to full you are without reading the number.
	_bank["pickup"] = _wav(_norm(_mix(
		_tone(0.16, 880.0, 880.0, 16.0),
		_tone(0.12, 1320.0, 1320.0, 22.0), 0.0, 0.4
	)))

	# Refusal: same length as a pickup, none of the brightness.
	_bank["pouch_full"] = _wav(_norm(_mix(
		_tone(0.13, 168.0, 118.0, 22.0, Wave.TRI),
		_noise(0.10, 30.0, 500.0, false, 112), 0.0, 0.6
	)))

	# One tap per seed banked, so a big deposit becomes a satisfying run of them.
	_bank["deposit"] = _wav(_norm(_mix(
		_tone(0.11, 420.0, 300.0, 26.0, Wave.TRI),
		_noise(0.06, 44.0, 1900.0, false, 113), 0.0, 0.45
	)))

	# The toll draining the bank. Deliberately coin-like and slightly harsh: you are spending.
	_bank["toll_tick"] = _wav(_norm(_mix(
		_tone(0.07, 1180.0, 1180.0, 42.0, Wave.SQUARE),
		_tone(0.09, 1760.0, 1700.0, 34.0), 0.0, 0.35
	)))

	# Heavy stone sinking. Long enough to cover the barrier's travel.
	var grind := _am(_noise(0.85, 2.2, 900.0, false, 114), 22.0, 0.4)
	grind = _mix(grind, _tone(0.80, 132.0, 58.0, 3.4, Wave.SAW), 0.0, 0.4)
	_bank["gate_open"] = _wav(_norm(grind))

	# A sunseed is the only thing in the level worth a melody.
	var chime := _blank(0.9)
	chime = _mix(chime, _tone(0.5, 659.0, 659.0, 7.0), 0.0, 0.9)
	chime = _mix(chime, _tone(0.5, 988.0, 988.0, 7.0), 0.09, 0.8)
	chime = _mix(chime, _tone(0.6, 1319.0, 1319.0, 5.5), 0.18, 0.7)
	_bank["sunseed"] = _wav(_norm(chime))

	# Every sunseed found. The same chord as one sunseed, arrived at from below.
	var fanfare := _blank(1.7)
	var figure := [523.0, 659.0, 784.0, 1047.0, 1319.0]
	for i in figure.size():
		var last := i == figure.size() - 1
		fanfare = _mix(
			fanfare,
			_tone(0.9 if last else 0.34, figure[i], figure[i], 3.0 if last else 9.0, Wave.TRI),
			i * 0.14,
			1.0 if last else 0.7
		)
	_bank["fanfare"] = _wav(_norm(fanfare))


# --- synthesis --------------------------------------------------------------


func _blank(duration: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	out.fill(0.0)
	return out


func _shape(phase: float, wave: int) -> float:
	match wave:
		Wave.SINE:
			return sin(phase)
		Wave.TRI:
			return asin(sin(phase)) * (2.0 / PI)
		Wave.SQUARE:
			return 1.0 if sin(phase) >= 0.0 else -1.0
		_:
			return fposmod(phase, TAU) / PI - 1.0


## A pitched blip sweeping from `from_hz` to `to_hz` under an exponential decay of `decay`
## nepers per second. `bend` shapes the sweep: below 1.0 rushes the rise, above 1.0 delays it.
##
## The phase is integrated rather than computed from the current frequency, because a swept
## oscillator evaluated as sin(TAU * f * t) plays a different pitch than the one asked for.
func _tone(
	duration: float,
	from_hz: float,
	to_hz: float,
	decay: float,
	wave := Wave.SINE,
	bend := 1.0
) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var progress := float(i) / float(maxi(1, count - 1))
		phase += TAU * lerpf(from_hz, to_hz, pow(progress, bend)) / RATE
		out[i] = _shape(phase, wave) * exp(-decay * float(i) / RATE) * _edges(i, count)
	return out


## Filtered noise. `cutoff` is a one-pole corner; `highpass` keeps what the filter rejects
## instead of what it passes, which is the difference between a scuff and a snap.
func _noise(
	duration: float,
	decay: float,
	cutoff: float,
	highpass := false,
	noise_seed := 1
) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var coefficient := clampf(1.0 - exp(-TAU * cutoff / RATE), 0.0, 1.0)
	var low := 0.0
	for i in count:
		var raw := rng.randf_range(-1.0, 1.0)
		low += coefficient * (raw - low)
		var value := (raw - low) if highpass else low
		out[i] = value * exp(-decay * float(i) / RATE) * _edges(i, count)
	return out


## Ring a buffer with a slow tremolo, which turns flat noise into a rattle or a grind.
func _am(buffer: PackedFloat32Array, hz: float, depth: float) -> PackedFloat32Array:
	for i in buffer.size():
		var wobble := 1.0 - depth * 0.5 * (1.0 - cos(TAU * hz * float(i) / RATE))
		buffer[i] *= wobble
	return buffer


func _mix(
	base: PackedFloat32Array, layer: PackedFloat32Array, at := 0.0, gain := 1.0
) -> PackedFloat32Array:
	var start := int(at * RATE)
	var needed := start + layer.size()
	if needed > base.size():
		var was := base.size()
		base.resize(needed)
		for i in range(was, needed):
			base[i] = 0.0
	for i in layer.size():
		base[start + i] += layer[i] * gain
	return base


## Scale to a fixed peak. Layered synthesis makes gain staging guesswork otherwise, and a
## lowpassed noise burst is far quieter than the tone sitting on top of it.
func _norm(buffer: PackedFloat32Array, peak := 0.92) -> PackedFloat32Array:
	var loudest := 0.0
	for value in buffer:
		loudest = maxf(loudest, absf(value))
	if loudest < 0.0001:
		return buffer
	var gain := peak / loudest
	for i in buffer.size():
		buffer[i] *= gain
	return buffer


## Turn a buffer into one that can loop without a click, by folding its tail back over its
## head and dropping the tail. The seam then joins two samples that were already neighbours.
func _loop(buffer: PackedFloat32Array, fade := 0.14) -> PackedFloat32Array:
	var overlap := mini(int(fade * RATE), buffer.size() / 2)
	if overlap < 1:
		return buffer
	var kept := buffer.size() - overlap
	var out := PackedFloat32Array()
	out.resize(kept)
	for i in kept:
		out[i] = buffer[i]
	for i in overlap:
		out[i] = lerpf(buffer[kept + i], buffer[i], float(i) / float(overlap))
	return out


## A couple of milliseconds of ramp at each end. Without it a buffer that starts or stops on a
## non-zero sample clicks, and slow-decaying sounds always stop on a non-zero sample.
func _edges(i: int, count: int) -> float:
	const RAMP := 48
	return minf(1.0, minf(float(i), float(count - 1 - i)) / RAMP)


func _wav(samples: PackedFloat32Array, looping := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(roundf(clampf(samples[i], -1.0, 1.0) * 32767.0)))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
