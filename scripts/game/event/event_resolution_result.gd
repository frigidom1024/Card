class_name EventResolutionResult
extends RefCounted

const CardDataScript = preload("res://scripts/card/card_data.gd")

enum Failure { NONE, INVALID_EVENT, INVALID_INDEX, SOLD_OUT, INSUFFICIENT_GOLD, HAND_FULL, ALREADY_RESOLVED }

var success := false
var failure: Failure = Failure.NONE
var granted_card: CardDataScript
var gold_delta := 0


static func rejected(reason: Failure):
	var result = load("res://scripts/game/event/event_resolution_result.gd").new()
	result.failure = reason
	return result