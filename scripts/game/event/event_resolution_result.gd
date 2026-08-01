class_name EventResolutionResult
extends RefCounted

enum Failure { NONE, INVALID_EVENT, INVALID_INDEX, SOLD_OUT, INSUFFICIENT_GOLD, HAND_FULL, ALREADY_RESOLVED }

var success := false
var failure: Failure = Failure.NONE
var granted_card: CardData
var gold_delta := 0


static func rejected(reason: Failure) -> EventResolutionResult:
	var result := EventResolutionResult.new()
	result.failure = reason
	return result
