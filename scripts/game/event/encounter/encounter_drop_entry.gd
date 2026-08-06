class_name EncounterDropEntry
extends Resource

## One independently rolled reward authored on an encounter content resource.
## GOLD uses gold_amount; CARD uses card_data.
enum Kind { GOLD, CARD }

@export var kind: Kind = Kind.GOLD
@export_range(0.0, 1.0, 0.01) var chance := 1.0
@export var gold_amount := 0
@export var card_data: CardData


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if chance < 0.0 or chance > 1.0:
		errors.append("chance must be between 0.0 and 1.0")
	if kind == Kind.GOLD and gold_amount <= 0:
		errors.append("gold entries require gold_amount greater than 0")
	if kind == Kind.CARD and card_data == null:
		errors.append("card entries require card_data")
	return errors
