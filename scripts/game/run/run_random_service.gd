class_name RunRandomService
extends RefCounted

## Owns independent random streams for one run.
##
## A non-negative seed makes all streams deterministic and replayable. The
## default seed uses a randomized master stream once, then derives each stream
## from it so consumers never share mutable RNG state.

var _market_rng := RandomNumberGenerator.new()
var _treasure_rng := RandomNumberGenerator.new()
var _encounter_reward_rng := RandomNumberGenerator.new()


func _init() -> void:
	configure()


func configure(seed_value: int = -1) -> void:
	var master := RandomNumberGenerator.new()
	if seed_value < 0:
		master.randomize()
	else:
		master.seed = seed_value
	_market_rng = _create_stream(master.randi())
	_treasure_rng = _create_stream(master.randi())
	_encounter_reward_rng = _create_stream(master.randi())


func market_rng() -> RandomNumberGenerator:
	return _market_rng


func treasure_rng() -> RandomNumberGenerator:
	return _treasure_rng


func encounter_reward_rng() -> RandomNumberGenerator:
	return _encounter_reward_rng


func _create_stream(stream_seed: int) -> RandomNumberGenerator:
	var stream := RandomNumberGenerator.new()
	stream.seed = stream_seed
	return stream
