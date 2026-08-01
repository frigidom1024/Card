class_name LastCardDefenseDoubleRule
extends CardRule


func execute(context: CardResolutionContext, draft: CardResolutionDraft) -> CardResolutionDraft:
	if context != null and draft != null and context.is_last_card():
		draft.defense *= 2
	return draft
