class_name FirstCardDamageDoubleRule
extends CardRule


func execute(context: CardResolutionContext, draft: CardResolutionDraft) -> CardResolutionDraft:
	if context != null and draft != null and context.is_first_card():
		draft.damage *= 2
	return draft
