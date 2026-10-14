extends Control
## Script attaccato da MKGloss.set_tip a un Control qualsiasi (Label, PanelContainer, TextureRect…):
## il suggerimento è in BBCode e va a capo invece di uscire dallo schermo.


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text == "":
		return null
	return MKGloss.tip_node(for_text)
