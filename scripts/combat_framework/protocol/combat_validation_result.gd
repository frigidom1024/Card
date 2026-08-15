class_name CombatValidationResult
extends RefCounted

var valid: bool = true
var reason_code: StringName = &""
var message: String = ""


static func accepted() -> CombatValidationResult:
	return CombatValidationResult.new()


static func rejected(code: StringName, detail: String = "") -> CombatValidationResult:
	var result := CombatValidationResult.new()
	result.valid = false
	result.reason_code = code
	result.message = detail
	return result
