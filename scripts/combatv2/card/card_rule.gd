class_name CardRule
extends Resource


@export var description:String

func execute(context: CardResolutionContext, draft: CardResolutionDraft) -> CardResolutionDraft:
	return draft
