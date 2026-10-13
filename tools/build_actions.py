#!/usr/bin/env python3
"""Carte Azione base, Azioni Avanzate e Ferita di Mage Knight.

Uscite (rigenerabili):
  data/cards_basic.json      carte Azione base (standard + specifiche degli eroi) + Ferita + mazzi iniziali
  data/cards_aa.json         Azioni Avanzate (base, Legione Perduta, Ultimate Edition, fan "Rise of the Forgemaster")
  data/specials_actions.json descrizione di ogni ["special", nome] / ["mod", nome] usato da queste carte
  assets/cards/<id>.webp     immagine di ogni carta (500x700, WebP q85) + back_action.webp / back_aa.webp

Uso:  python3 tools/build_actions.py            (dati + immagini mancanti)
      python3 tools/build_actions.py --images   (rigenera tutte le immagini)
      python3 tools/build_actions.py --check    (solo validazione)
Sorgenti: /home/claude/work/card_index.json (tools/card_index.py) e le immagini del modulo TTS.
"""
import json, os, sys, glob, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
INDEX = '/home/claude/work/card_index.json'
IMGDIR = '/mnt/user-data/uploads/Mage Knight/Mods/Images'
CARD_W, CARD_H = 500, 700

# ---------------------------------------------------------------- DSL helpers
def ch(*opts):
    """["choice", [[effetti], ...]] ; un'opzione [] = rinunciare a un effetto facoltativo ("puoi...")."""
    return ["choice", [list(o) for o in opts]]

def sp(name, **p):
    return ["special", name, p]

def md(name, **p):
    return ["mod", name, p]

def MV(n): return ["move", n]
def INF(n): return ["influence", n]
def HEAL(n): return ["heal", n]
def ATT(n, e="phys", k="melee"): return ["attack", n, e, k] if (e, k) != ("phys", "melee") else ["attack", n]
def RNG(n, e="phys"): return ATT(n, e, "ranged")
def SIE(n, e="phys"): return ATT(n, e, "siege")
def BLK(n, e="phys"): return ["block", n, e] if e != "phys" else ["block", n]
def MANA(c): return ["mana", c]
def CRY(c): return ["crystal", c]

BASIC4 = ["red", "blue", "green", "white"]
ANY_TOKEN = ch(*[[MANA(c)] for c in ["red", "blue", "green", "white", "gold", "black"]])
OPT = lambda *eff: ch([], list(eff))          # effetto facoltativo
PASSABLE = ["plains", "hills", "forest", "wasteland", "desert", "swamp"]

# ---------------------------------------------------------------- card builder
CARDS = []

def card(id, set, type, color, name_it, name_en, basic, powered, t_basic, t_powered, src,
         hero="", replaces="", copies=1, combat_only=False, note="", impl=True, colors=None, side=True,
         text_en=None):
    c = {"id": id, "set": set, "type": type, "hero": hero}
    if replaces:
        c["replaces"] = replaces
    c.update({"color": color})
    if colors:
        c["colors"] = colors
    c.update({"name_it": name_it, "name_en": name_en, "basic": basic, "powered": powered, "side": side,
              "combat_only": combat_only, "text_it": {"basic": t_basic, "powered": t_powered},
              "img": f"assets/cards/{id}.webp", "copies": copies, "impl": impl, "note": note})
    if text_en:
        c["text_en"] = {"basic": text_en[0], "powered": text_en[1]}
    c["_src"] = src
    CARDS.append(c)
    return c

# sorgenti immagine: (suffisso del foglio inglese, indice) ; lang 'it' se esiste il foglio italiano
S_BASIC = 'C59FE39ACECEF3A1A2AF080FF9'      # 7x4, carte base standard + eroi (solo inglese)
S_AA = '403BF15ECEE4CAA1D787C8B596'         # 8x6, Azioni Avanzate ufficiali (c'è il foglio italiano)
S_ROTF = '2B8612FC3DA8FB481BE3A2C5EC'       # 8x6, Azioni Avanzate fan "Rise of the Forgemaster" (inglese)
S_ROTF_B = 'DF51CBDE935DB62F6A7BB45544'     # 3x2, Jormund + carte base sostitutive RotF
S_DUSC = 'DA384C9F36B046A9411DAD03EEA858C065743D1D'
S_MALEK = 'DEAC4D56541B5DF947B14A95B2011D4A5C287F8'
S_ZIRT = 'DFB8CABFA50534BB66185504CBCC47B6EF798AF5'
S_MEVOK = '48F627EF6FA437B004C4BA2D8E72BB3AEFB91C1BE'
S_CORAL = 'DD892900380E65144B8723024100271CC0F40342'
WOUND_IMG = '9156F6318D06B1DDFD6AD366B6'
BACK_IMG = '5B55DB801B931B483543CF8BD70E9705E306'

# ============================================================== BASIC ACTIONS (standard)
B = dict(set="base", type="basic")
card("stamina", color="blue", name_it="Resistenza", name_en="Stamina", basic=[MV(2)], powered=[MV(4)],
     t_basic="Movimento 2", t_powered="Movimento 4", src=(S_BASIC, 14), copies=2, **B)
card("determination", color="blue", name_it="Determinazione", name_en="Determination",
     basic=[ch([ATT(2)], [BLK(2)])], powered=[BLK(5)],
     t_basic="Attacco o Blocco 2", t_powered="Blocco 5", src=(S_BASIC, 16), combat_only=True, **B)
card("crystallize", color="blue", name_it="Cristallizzare", name_en="Crystallize",
     basic=[["pay_mana", "basic", [CRY("$paid")]]], powered=[CRY("basic")],
     t_basic="Quando giochi questa carta, paga anche un mana di un colore base. Guadagni un cristallo di quel colore nel tuo Inventario.",
     t_powered="Guadagni un cristallo di un colore qualsiasi nel tuo Inventario.",
     src=(S_BASIC, 15), note="Di Giorno il mana oro pagato vale come un colore base a scelta (cristallo di quel colore). Potenziato: colore base a scelta.", **B)
card("march", color="green", name_it="Marcia", name_en="March", basic=[MV(2)], powered=[MV(4)],
     t_basic="Movimento 2", t_powered="Movimento 4", src=(S_BASIC, 0), copies=2, **B)
card("tranquility", color="green", name_it="Tranquillità", name_en="Tranquility",
     basic=[ch([HEAL(1)], [["draw", 1]])], powered=[ch([HEAL(2)], [["draw", 2]])],
     t_basic="Cura 1 oppure pesca una carta.", t_powered="Cura 2 oppure pesca due carte.",
     src=(S_BASIC, 1), note="Carta Cura (icona in alto a sinistra): non giocabile durante il combattimento.", **B)
card("concentration", color="green", name_it="Concentrazione", name_en="Concentration",
     basic=[ch([MANA("blue")], [MANA("white")], [MANA("red")])], powered=[["boost_next", 2]],
     t_basic="Guadagni un segnalino mana blu, bianco o rosso.",
     t_powered="Quando giochi questa carta, gioca con essa un'altra carta Azione. Ottieni l'effetto più potente di quella carta gratuitamente. Se quell'effetto ti fornisce Movimento, Influenza, Blocco o qualsiasi tipo di Attacco, ottieni quel valore più 2.",
     src=(S_BASIC, 2),
     note="boost_next qui significa: la carta Azione giocata subito dopo (obbligatoria, dalla mano) usa l'effetto potenziato SENZA pagare mana e ogni valore di Movimento/Influenza/Blocco/Attacco che fornisce riceve +n (se l'effetto è una scelta, il bonus va al valore scelto). Effetti 'composti': vedi regolamento (vale come un unico effetto).", **B)
card("swiftness", color="white", name_it="Rapidità", name_en="Swiftness", basic=[MV(2)], powered=[RNG(3)],
     t_basic="Movimento 2", t_powered="Attacco a Distanza 3", src=(S_BASIC, 7), copies=2, **B)
card("mana_draw", color="white", name_it="Pescare Mana", name_en="Mana Draw",
     basic=[["extra_die", 1]], powered=[sp("mana_draw", dice=1, tokens=2)],
     t_basic="Puoi utilizzare un dado mana addizionale dalla Riserva in questo turno.",
     t_powered="Prendi un dado mana dalla Riserva e impostalo su un colore qualsiasi tranne l'oro. Guadagni due segnalini mana di quel colore. Non ritirare questo dado quando lo rimetti nella Riserva.",
     src=(S_BASIC, 9), note="Nome italiano dalla Guida alla prima partita ('Pescare Mana'; il modulo usa 'Prelievo di Mana').", **B)
card("promise", color="white", name_it="Promessa", name_en="Promise", basic=[INF(2)], powered=[INF(4)],
     t_basic="Influenza 2", t_powered="Influenza 4", src=(S_BASIC, 8), **B)
card("improvisation", color="red", name_it="Improvvisazione", name_en="Improvisation",
     basic=[["discard", 1, [ch([MV(3)], [INF(3)], [ATT(3)], [BLK(3)])]]],
     powered=[["discard", 1, [ch([MV(5)], [INF(5)], [ATT(5)], [BLK(5)])]]],
     t_basic="Scarta un'altra carta dalla tua mano per ottenere Movimento 3, Influenza 3, Attacco 3 o Blocco 3.",
     t_powered="Scarta un'altra carta dalla tua mano per ottenere Movimento 5, Influenza 5, Attacco 5 o Blocco 5.",
     src=(S_BASIC, 23), note="La carta scartata non può essere una Ferita.", **B)
card("threaten", color="red", name_it="Minacciare", name_en="Threaten", basic=[INF(2)], powered=[INF(5), ["rep", -1]],
     t_basic="Influenza 2", t_powered="Influenza 5. Reputazione -1.", src=(S_BASIC, 22), **B)
card("rage", color="red", name_it="Furia", name_en="Rage", basic=[ch([ATT(2)], [BLK(2)])], powered=[ATT(4)],
     t_basic="Attacco o Blocco 2", t_powered="Attacco 4", src=(S_BASIC, 21), copies=2, combat_only=True,
     note="Nome italiano dalla Guida alla prima partita ('Furia'; il modulo usa 'Rabbia').", **B)

# ============================================================== BASIC ACTIONS specific to heroes (official)
UE2 = "Seconda carta specifica dell'eroe dell'Ultimate Edition (nel mazzo del modulo); nella prima edizione l'eroe aveva solo "
card("battle_versatility", set="base", type="basic", hero="arythea", replaces="rage", color="red",
     name_it="Versatilità in Battaglia", name_en="Battle Versatility",
     basic=[ch([ATT(2)], [BLK(2)], [RNG(1)])],
     powered=[ch([ATT(4)], [BLK(4)], [ATT(3, "fire")], [BLK(3, "fire")], [RNG(3)], [SIE(2)])],
     t_basic="Attacco 2, Blocco 2 oppure Attacco a Distanza 1.",
     t_powered="Attacco 4, Blocco 4, Attacco di Fuoco 3, Blocco di Fuoco 3, Attacco a Distanza 3 oppure Attacco d'Assedio 2.",
     src=(S_BASIC, 24), combat_only=True)
card("mana_pull", set="base", type="basic", hero="arythea", replaces="mana_draw", color="white",
     name_it="Attrazione del Mana", name_en="Mana Pull",
     basic=[["extra_die", 1], md("extra_black_die_any")], powered=[sp("mana_draw", dice=2, tokens=1)],
     t_basic="Puoi utilizzare un dado mana addizionale dalla Riserva in questo turno. Se quel dado è nero, usalo per produrre mana di qualsiasi colore.",
     t_powered="Prendi due dadi mana dalla Riserva e imposta ciascuno su un colore qualsiasi tranne l'oro. Guadagni un segnalino mana di ciascuno di quei colori. Non ritirare questi dadi quando li rimetti nella Riserva.",
     src=(S_BASIC, 13), note=UE2 + "Versatilità in Battaglia.")
card("will_focus", set="base", type="basic", hero="goldyx", replaces="concentration", color="green",
     name_it="Forza di Volontà", name_en="Will Focus",
     basic=[ch([MANA("blue")], [MANA("white")], [MANA("red")], [CRY("green")])], powered=[["boost_next", 3]],
     t_basic="Guadagni un segnalino mana blu, bianco o rosso, oppure un cristallo verde nel tuo Inventario.",
     t_powered="Quando giochi questa carta, gioca con essa un'altra carta Azione. Ottieni l'effetto più potente di quella carta gratuitamente. Se quell'effetto ti fornisce Movimento, Influenza, Blocco o qualsiasi tipo di Attacco, ottieni quel valore più 3.",
     src=(S_BASIC, 6), note="boost_next: vedi Concentrazione.")
card("crystal_joy", set="base", type="basic", hero="goldyx", replaces="crystallize", color="blue",
     name_it="Gioia dei Cristalli", name_en="Crystal Joy",
     basic=[["pay_mana", "basic", [CRY("$paid")]], md("return_card_end_turn", wound_ok=False)],
     powered=[CRY("basic"), md("return_card_end_turn", wound_ok=True)],
     t_basic="Paga un mana di un qualsiasi colore base per guadagnare un cristallo di quel colore nel tuo Inventario. Alla fine del tuo turno, puoi scartare un'altra carta non-Ferita per riprendere in mano questa carta.",
     t_powered="Guadagni un cristallo di un qualsiasi colore base nel tuo Inventario. Alla fine del tuo turno, puoi scartare un'altra carta, anche una Ferita, per riprendere in mano questa carta.",
     src=(S_BASIC, 19), note=UE2 + "Forza di Volontà.")
card("noble_manners", set="base", type="basic", hero="norowas", replaces="promise", color="white",
     name_it="Nobili Maniere", name_en="Noble Manners",
     basic=[INF(2), md("interaction_bonus", fame=1)], powered=[INF(4), md("interaction_bonus", fame=1, rep=1)],
     t_basic="Influenza 2. Fama +1 se la usi durante un'interazione.",
     t_powered="Influenza 4. Fama +1 e Reputazione +1 se la usi durante un'interazione.",
     src=(S_BASIC, 12), note="Nel Lua del modulo è chiamata 'Noble Promise'; la carta stampata è 'Noble Manners'.")
card("rejuvenate", set="base", type="basic", hero="norowas", replaces="tranquility", color="green",
     name_it="Ringiovanire", name_en="Rejuvenate",
     basic=[ch([HEAL(1)], [["draw", 1]], [MANA("green")], [["ready_unit", 2]])],
     powered=[ch([HEAL(2)], [["draw", 2]], [CRY("green")], [["ready_unit", 3]])],
     t_basic="Cura 1, pesca una carta, guadagni un segnalino mana verde oppure rendi pronta un'Unità di Livello I o II.",
     t_powered="Cura 2, pesca due carte, guadagni un cristallo verde nel tuo Inventario oppure rendi pronta un'Unità di Livello I, II o III.",
     src=(S_BASIC, 5), note=UE2 + "Nobili Maniere. Cura non utilizzabile in combattimento.")
card("cold_toughness", set="base", type="basic", hero="tovak", replaces="determination", color="blue",
     name_it="Tenacia Gelida", name_en="Cold Toughness",
     basic=[ch([ATT(2)], [BLK(3, "ice")])], powered=[BLK(5, "ice"), sp("block_per_enemy_ability", n=1, elem="ice")],
     t_basic="Attacco 2 oppure Blocco di Ghiaccio 3.",
     t_powered="Blocco di Ghiaccio 5. Ottieni +1 Blocco di Ghiaccio per ogni abilità o colore d'attacco raffigurato sul gettone del nemico che blocchi (a meno che non abbia Immunità Arcana), oppure per ogni mana speso da un avversario durante l'attacco.",
     src=(S_BASIC, 20), combat_only=True)
card("instinct", set="base", type="basic", hero="tovak", replaces="improvisation", color="red",
     name_it="Istinto", name_en="Instinct",
     basic=[ch([MV(2)], [INF(2)], [ATT(2)], [BLK(2)])], powered=[ch([MV(4)], [INF(4)], [ATT(4)], [BLK(4)])],
     t_basic="Movimento 2, Influenza 2, Attacco 2 o Blocco 2.", t_powered="Movimento 4, Influenza 4, Attacco 4 o Blocco 4.",
     src=(S_BASIC, 27), note=UE2 + "Tenacia Gelida.")
card("swift_reflexes", set="ll", type="basic", hero="wolfhawk", replaces="swiftness", color="white",
     name_it="Riflessi Rapidi", name_en="Swift Reflexes",
     basic=[ch([MV(2)], [RNG(1)], [sp("reduce_enemy_attack", n=1)])],
     powered=[ch([MV(4)], [RNG(3)], [sp("reduce_enemy_attack", n=2)])],
     t_basic="Movimento 2, Attacco a Distanza 1, oppure riduci di 1 un attacco nemico.",
     t_powered="Movimento 4, Attacco a Distanza 3, oppure riduci di 2 un attacco nemico.",
     src=(S_BASIC, 10), note="La riduzione dell'attacco si usa nella fase di Blocco (prima di bloccare/assegnare i danni).")
card("tirelessness", set="ll", type="basic", hero="wolfhawk", replaces="stamina", color="blue",
     name_it="Instancabilità", name_en="Tirelessness",
     basic=[MV(2), md("move_card_bonus", n=1, cards=1)], powered=[MV(4), md("move_card_bonus", n=1, cards="all")],
     t_basic="Movimento 2. La prossima carta che fornisce Movimento (incluse le carte giocate sul fianco) dà +1 Movimento in questo turno.",
     t_powered="Movimento 4. Ogni altra carta che fornisce Movimento (incluse le carte giocate sul fianco) dà +1 Movimento in questo turno.",
     src=(S_BASIC, 17))
card("savage_harvesting", set="krang", type="basic", hero="krang", replaces="march", color="green",
     name_it="Raccolta Selvaggia", name_en="Savage Harvesting",
     basic=[MV(2), md("crystal_on_move", times=1)], powered=[MV(4), md("crystal_on_move", times="each")],
     t_basic="Movimento 2. Una volta in questo turno, quando muovi in uno spazio, puoi scartare una carta per guadagnare un cristallo dello stesso colore. Se scarti un Artefatto puoi sceglierne il colore.",
     t_powered="Movimento 4. Ogni volta che muovi in uno spazio in questo turno puoi scartare una carta per guadagnare un cristallo dello stesso colore. Se scarti un Artefatto puoi sceglierne il colore.",
     src=(S_BASIC, 3))
card("ruthless_coercion", set="krang", type="basic", hero="krang", replaces="threaten", color="red",
     name_it="Coercizione Spietata", name_en="Ruthless Coercion",
     basic=[INF(2), md("recruit_discount", n=2, units=1, rep=-1)],
     powered=[INF(6), ["rep", -1], md("ready_units_for_influence", per_level=2, max_level=2)],
     t_basic="Influenza 2. Puoi ottenere uno sconto di 2 sul costo di reclutamento di un'Unità. Se recluti quell'Unità in questo turno, Reputazione -1.",
     t_powered="Influenza 6. Reputazione -1. Puoi rendere pronte le Unità di Livello I e II che controlli pagando 2 punti Influenza per livello dell'Unità.",
     src=(S_BASIC, 26))
card("druidic_paths", set="tezla", type="basic", hero="braevalar", replaces="stamina", color="blue",
     name_it="Sentieri Druidici", name_en="Druidic Paths",
     basic=[MV(2), sp("reduce_space_cost", n=1, min=2)],
     powered=[MV(4), ch(*[[["terrain", {t: "-1", "min": 2}]] for t in PASSABLE])],
     t_basic="Movimento 2. Il costo di Movimento di uno spazio viene ridotto di 1 in questo turno, fino a un minimo di 2.",
     t_powered="Movimento 4. Il costo di Movimento di un tipo di terreno viene ridotto di 1 in questo turno, fino a un minimo di 2.",
     src=(S_BASIC, 18))
card("one_with_the_land", set="tezla", type="basic", hero="braevalar", replaces="march", color="green",
     name_it="Tutt'uno con la Terra", name_en="One with the Land",
     basic=[ch([MV(2)], [HEAL(1)], [BLK(2)])], powered=[ch([MV(4)], [HEAL(2)], [sp("block_by_terrain")])],
     t_basic="Movimento 2, Cura 1 oppure Blocco 2.",
     t_powered="Movimento 4, Cura 2 oppure Blocco pari al costo di Movimento non modificato dello spazio in cui ti trovi (Montagne 5, Laghi 2). È un Blocco di Fuoco di Giorno e un Blocco di Ghiaccio di Notte.",
     src=(S_BASIC, 4), note="Cura non utilizzabile in combattimento.")

# ============================================================== BASIC ACTIONS of fan / homemade heroes
F = dict(set="fan", type="basic")
card("quick_witted", hero="coral", replaces="swiftness", color="white", name_it="Prontezza di Spirito", name_en="Quick-Witted",
     basic=[ch([MV(2)], [INF(2)])], powered=[ch([RNG(3)], [INF(4)])],
     t_basic="Movimento 2 oppure Influenza 2", t_powered="Attacco a Distanza 3 oppure Influenza 4",
     src=(S_CORAL, 0), note="Eroe fan Coral.", **F)
card("tempered_steel", hero="coral", replaces="rage", color="red", name_it="Acciaio Temprato", name_en="Tempered Steel",
     basic=[ch([BLK(2), md("delayed_attack", n=1)], [BLK(1), md("delayed_attack", n=2)])],
     powered=[ch([sp("attack_vs_resistant", n=4, n_if_resist=6)], [sp("block_vs_swift", n=4, n_if_swift=6)])],
     t_basic="Blocco 2 e poi Attacco 1 durante la tua fase Attacco, oppure Blocco 1 e poi Attacco 2 durante la tua fase Attacco.",
     t_powered="Attacco 4 (Attacco 6 se un qualsiasi nemico bersaglio di questo attacco ha delle resistenze) oppure Blocco 4 (Blocco 6 contro un attacco con Rapidità).",
     src=(S_CORAL, 1), combat_only=True, note="Eroe fan Coral.", **F)
card("axe_throw", hero="ymirgh", replaces="swiftness", color="white", name_it="Lancio dell'Ascia", name_en="Axe Throw",
     basic=[ch([MV(2)], [RNG(1)])], powered=[sp("attack_with_kill_reward", n=3, kind="ranged", fame_once=1)],
     t_basic="Movimento 2 oppure Attacco a Distanza 1.",
     t_powered="Attacco a Distanza 3. Fama +1 se hai sconfitto almeno un nemico con questo attacco.",
     src=(S_BASIC, 11), note="Eroe 'homemade' Ymirgh.", **F)
card("battle_rage", hero="ymirgh", replaces="rage", color="red", name_it="Furia di Battaglia", name_en="Battle Rage",
     basic=[ATT(2), sp("attack_per_combat_wound", n=1, max=1)], powered=[ATT(4), sp("attack_per_combat_wound", n=1, max=4)],
     t_basic="Attacco 2. Puoi aumentare questo attacco di 1 se hai ricevuto una carta Ferita durante questa battaglia.",
     t_powered="Attacco 4. Puoi aumentare questo attacco di 1 per ogni carta Ferita che hai ricevuto durante questa battaglia (max 4).",
     src=(S_BASIC, 25), combat_only=True, note="Eroe 'homemade' Ymirgh.", **F)
card("hidden_river", hero="duscenia", replaces="stamina", color="blue", name_it="Fiume Nascosto", name_en="Hidden River",
     basic=[MV(2), sp("reduce_space_cost", n=2, min=1, terrain="forest"),
            md("terrain_count_reward", terrain="forest", count=2, effects=[MANA("blue")])],
     powered=[MV(4), ["terrain", {"forest": "-2", "min": 1}],
              md("terrain_count_reward", terrain="forest", count=2, effects=[CRY("blue")])],
     t_basic="Movimento 2. Il costo di Movimento di una singola Foresta viene ridotto di 2, fino a un minimo di 1. Se in questo turno attraversi due Foreste, guadagni un segnalino mana blu.",
     t_powered="Movimento 4. Il costo di Movimento delle Foreste viene ridotto di 2, fino a un minimo di 1. Se in questo turno attraversi due Foreste, guadagni un cristallo blu.",
     src=(S_DUSC, 0), note="Eroe fan Duscenia.", **F)
card("duscenia_regeneration", hero="duscenia", replaces="tranquility", color="green", name_it="Rigenerazione (Duscenia)", name_en="Regeneration (Duscenia)",
     basic=[ch([sp("wounds_sideways", n=1, mult=2, then="discard")], [sp("heal_any_pile", n=1, discard_max=1)], [MANA("green")])],
     powered=[ch([sp("wounds_sideways", n=2, bonus=1, throw=1)], [sp("heal_any_pile", n=2, discard_max=1)], [CRY("green")])],
     t_basic="Gioca 1 Ferita come carta sul fianco con effetto doppio e poi scartala, Cura 1 (utilizzabile anche sulla pila degli scarti), oppure guadagni un segnalino mana verde.",
     t_powered="Gioca 2 Ferite come carte sul fianco, poi aumenta di 1 l'effetto totale e getta via 1 di quelle Ferite, Cura 2 (1 Cura utilizzabile sulla pila degli scarti), oppure guadagni un cristallo verde.",
     src=(S_DUSC, 1), note="Eroe fan Duscenia. Stesso nome dell'Azione Avanzata 'Rigenerazione': id diverso.", **F)
card("transmutation", hero="jormund", replaces="swiftness", color="white", name_it="Trasmutazione", name_en="Transmutation",
     basic=[MV(2), OPT(sp("rotf_flip_die"))],
     powered=[ch([MV(4)], [RNG(3)], [sp("rotf_mana_shard", color="basic"), MANA("basic")], [sp("rotf_cumbersome")])],
     t_basic="Movimento 2, e puoi girare un dado mana di un colore base nella Riserva.",
     t_powered="Movimento 4, Attacco a Distanza 3, guadagni un frammento di mana e un segnalino mana di colori base a scelta, oppure un nemico bersaglio ottiene Ingombrante.",
     src=(S_ROTF_B, 1), impl=False, note="Eroe fan Jormund (meccaniche di 'Rise of the Forgemaster': frammenti di mana, girare dadi, Ingombrante).", **F)
card("resilience", hero="jormund", replaces="rage", color="red", name_it="Resilienza", name_en="Resilience",
     basic=[ch([ATT(2)], [BLK(2)], [sp("ignore_hero_damage", phys=3, other=2)], [sp("rotf_potion", action="refill")])],
     powered=[ATT(4), sp("rotf_potion", action="gain_if_kill")],
     t_basic="Attacco 2, Blocco 2, ignora i prossimi 3 punti di danno assegnati al tuo eroe da un singolo attacco fisico (o 2 punti da un attacco non fisico), oppure ricarica una Pozione.",
     t_powered="Attacco 4. Alla fine del combattimento, guadagni una Pozione se hai sconfitto un nemico con questo attacco.",
     src=(S_ROTF_B, 0), impl=False, combat_only=True, note="Eroe fan Jormund (Pozioni di 'Rise of the Forgemaster').", **F)
card("bounty_hunter", hero="malek", replaces="promise", color="white", colors=["white", "red"],
     name_it="Cacciatore di Taglie", name_en="Bounty Hunter",
     basic=[ch([INF(2)], [INF(3), ["rep", -1]])], powered=[ch([INF(4)], [sp("bounty", armor=1, fame=1, rep=1, range=2)])],
     t_basic="Influenza 2 oppure Influenza 3, Reputazione -1",
     t_powered="Influenza 4, oppure metti una Taglia (scudo) su un qualsiasi nemico visibile. Quel nemico ha Armatura -1. Se lo sconfiggi, guadagni Fama +1 e Reputazione +1. Se è infuriato, puoi iniziare il combattimento a 2 spazi di distanza (solo fase a Distanza).",
     src=(S_MALEK, 1), note="Eroe fan Malek. Carta bicolore (bianco/rosso): si potenzia con uno dei due colori.", **F)
card("elemental_bullets", hero="malek", replaces="rage", color="red", colors=["red", "blue"],
     name_it="Proiettili Elementali", name_en="Elemental Bullets",
     basic=[ch([ATT(2)], [BLK(2)], [RNG(1)])],
     powered=[ch([ATT(4)], [RNG(3)], [RNG(2, "fire")], [RNG(2, "ice")], [SIE(2)])],
     t_basic="Attacco 2, Blocco 2 oppure Attacco a Distanza 1.",
     t_powered="Attacco 4, Attacco a Distanza 3, Attacco di Fuoco a Distanza 2, Attacco di Ghiaccio a Distanza 2 oppure Attacco d'Assedio 2.",
     src=(S_MALEK, 0), combat_only=True, note="Eroe fan Malek. Carta bicolore (rosso/blu).", **F)
card("spear_glare", hero="zirtae", replaces="determination", color="blue", name_it="Bagliore della Lancia", name_en="Spear Glare",
     basic=[ch([ATT(2)], [BLK(2)])], powered=[BLK(3), sp("enemy_attack_strip", what="one")],
     t_basic="Attacco 2 oppure Blocco 2.",
     t_powered="Blocco 3. Rimuovi un colore d'Attacco o un modificatore d'Attacco di un gettone nemico.",
     src=(S_ZIRT, 1), combat_only=True, note="Eroe fan Zirtae.", **F)
card("deadly_precision", hero="zirtae", replaces="rage", color="red", name_it="Precisione Letale", name_en="Deadly Precision",
     basic=[ch([ATT(2)], [BLK(2)])], powered=[ch([ATT(4)], [RNG(2)], [sp("convert_attack_card_to_ranged")])],
     t_basic="Attacco 2 oppure Blocco 2.",
     t_powered="Attacco 4 oppure Attacco a Distanza 2. In alternativa puoi usare questa carta con un'altra carta Attacco per trasformare il valore d'Attacco e gli elementi di quella carta in Attacco a Distanza, mantenendo gli elementi. Devi comunque pagare il mana per l'effetto potente della seconda carta.",
     src=(S_ZIRT, 0), combat_only=True, note="Eroe fan Zirtae.", **F)
card("infamous_reprisals", hero="mevok", replaces="promise", color="white", name_it="Rappresaglie Infami", name_en="Infamous Reprisals",
     basic=[INF(2), sp("mevok_reprisals", mode="basic")], powered=[sp("mevok_reprisals", mode="powered")],
     t_basic="X Rep è -5. Guadagni Influenza 2. Paga mana nero per usare la reputazione più bassa di un altro Cavaliere; quello perde 1 Reputazione. In solitario, aggiungi 3 alla tua reputazione attuale per questa interazione, fino a un massimo di +1.",
     t_powered="X Rep è -5. Guadagni Influenza 4 oppure aggiungi l'icona +/- a una singola Unità nell'offerta e guadagni Influenza pari al valore assoluto della tua reputazione. Paga mana nero, anche di giorno, per +1 Influenza ciascuno.",
     src=(S_MEVOK, 1), impl=False, note="Eroe fan Mevok (regole proprie sulla reputazione, testo ambiguo).", **F)
card("undead_horde", hero="mevok", replaces="rage", color="red", name_it="Orda di Non Morti", name_en="Undead Horde",
     basic=[ch([ATT(2)], [BLK(2)]), sp("mevok_horde", mode="basic")], powered=[ch([ATT(4)], [sp("mevok_horde", mode="activate")])],
     t_basic="Attacco 2, Blocco 2. Alla fine della fase paga i Costi di Rianimazione per qualsiasi numero di nemici sconfitti in quella fase. Puoi creare un'Orda. Mettili in un'Orda o in un'Abilità disponibile.",
     t_powered="Attacco 4 oppure attiva le tue Orde. Alla fine di una fase di combattimento, paga i Costi di Rianimazione per qualsiasi numero di nemici sconfitti in quella fase. Mettili in un'Orda o in un'Abilità disponibile.",
     src=(S_MEVOK, 0), impl=False, combat_only=True, note="Eroe fan Mevok (meccanica delle Orde di non morti).", **F)
# replacement starter cards of the fan campaign "Rise of the Forgemaster"
card("rotf_concentration", color="green", name_it="Concentrazione (RotF)", name_en="Concentration (RotF)",
     basic=[ch([MANA("blue")], [MANA("white")], [MANA("red")])], powered=[sp("play_with_bonus", bonus=2)],
     t_basic="Guadagni un segnalino mana blu, bianco o rosso.",
     t_powered="Gioca un'altra carta Azione dalla tua mano con un bonus di +2. Puoi usarne l'effetto base o quello più potente (gratuitamente).",
     src=(S_ROTF_B, 3), copies=1, note="Campagna fan 'Rise of the Forgemaster': sostituisce Concentrazione (anche nel mazzo di Jormund).", **F)
card("rotf_will_focus", color="green", name_it="Forza di Volontà (RotF)", name_en="Will Focus (RotF)",
     basic=[ch([MANA("blue")], [MANA("white")], [MANA("red")]), OPT(sp("recolor_crystal"))],
     powered=[sp("play_with_bonus", bonus=3)],
     t_basic="Guadagni un segnalino mana blu, bianco o rosso. Inoltre puoi cambiare il colore di un cristallo nel tuo Inventario in un qualsiasi colore base.",
     t_powered="Gioca un'altra carta Azione dalla tua mano con un bonus di +3. Puoi usarne l'effetto base o quello più potente (gratuitamente).",
     src=(S_ROTF_B, 2), note="Campagna fan 'Rise of the Forgemaster': sostituisce Forza di Volontà di Goldyx.", **F)
card("rotf_savage_harvesting", color="green", name_it="Raccolta Selvaggia (RotF)", name_en="Savage Harvesting (RotF)",
     basic=[MV(2), md("rotf_shard_on_move", times=1)], powered=[MV(4), md("rotf_shard_on_move", times="each")],
     t_basic="Movimento 2. Una volta in questo turno, quando muovi in uno spazio, puoi scartare una carta per guadagnare un frammento dello stesso colore.",
     t_powered="Movimento 4. Ogni volta che muovi in uno spazio in questo turno, puoi scartare una carta per guadagnare un frammento dello stesso colore.",
     src=(S_ROTF_B, 4), impl=False, note="Campagna fan 'Rise of the Forgemaster': sostituisce Raccolta Selvaggia di Krang (frammenti di mana).", **F)

# ============================================================== WOUND
card("wound", set="base", type="wound", color="", name_it="Ferita", name_en="Wound", basic=[], powered=[],
     t_basic="", t_powered="", src=("WHOLE", WOUND_IMG), side=False, copies=0,
     note="Non si può giocare né scartare (salvo effetti che lo consentono esplicitamente). Pila comune delle Ferite (s.decks.wounds).")

# ============================================================== ADVANCED ACTIONS (official)
def aa(id, set, color, name_it, name_en, basic, powered, tb, tp, idx, **kw):
    return card(id, set=set, type="aa", color=color, name_it=name_it, name_en=name_en, basic=basic, powered=powered,
                t_basic=tb, t_powered=tp, src=(S_AA, idx), **kw)

ICE_RES = " I nemici con Resistenza al Ghiaccio ignorano gli effetti non-Attacco delle carte blu."
FIRE_RES = " I nemici con Resistenza al Fuoco ignorano gli effetti non-Attacco delle carte rosse."

# --- base game (28): carte 65-92/377
aa("fire_bolt", "base", "red", "Saetta di Fuoco", "Fire Bolt", [CRY("red")], [RNG(3, "fire")],
   "Guadagni un cristallo rosso nel tuo Inventario.", "Attacco di Fuoco a Distanza 3", 0)
aa("ice_bolt", "base", "blue", "Saetta di Ghiaccio", "Ice Bolt", [CRY("blue")], [RNG(3, "ice")],
   "Guadagni un cristallo blu nel tuo Inventario.", "Attacco di Ghiaccio a Distanza 3", 1)
aa("swift_bolt", "base", "white", "Saetta Fulminea", "Swift Bolt", [CRY("white")], [RNG(4)],
   "Guadagni un cristallo bianco nel tuo Inventario.", "Attacco a Distanza 4", 2)
aa("crushing_bolt", "base", "green", "Saetta Devastante", "Crushing Bolt", [CRY("green")], [SIE(3)],
   "Guadagni un cristallo verde nel tuo Inventario.", "Attacco d'Assedio 3", 3)
aa("blood_rage", "base", "red", "Furia Sanguinaria", "Blood Rage",
   [ch([ATT(2)], [sp("take_wound"), ATT(5)])], [ch([ATT(4)], [sp("take_wound"), ATT(9)])],
   "Attacco 2. Puoi subire una Ferita per aumentare questo Attacco a 5.",
   "Attacco 4. Puoi subire una Ferita per aumentare questo Attacco a 9.", 4, combat_only=True,
   note="La Ferita va in mano e conta per il Colpo di Grazia.")
aa("ice_shield", "base", "blue", "Scudo di Ghiaccio", "Ice Shield", [BLK(3, "ice")],
   [BLK(3, "ice"), sp("block_armor_reduce", n=3, min=1)],
   "Blocco di Ghiaccio 3",
   "Blocco di Ghiaccio 3. Riduci di 3 l'Armatura di un nemico bloccato in questo modo. L'Armatura non può scendere sotto l'1.",
   5, combat_only=True, note="Fase di Blocco." + ICE_RES)
aa("agility", "base", "white", "Agilità", "Agility",
   [MV(2), md("move_to_attack", melee=1)], [MV(4), md("move_to_attack", melee=1, ranged=2)],
   "Movimento 2. Durante il combattimento in questo turno, puoi spendere punti Movimento per ottenere Attacco 1 per ogni punto speso.",
   "Movimento 4. Durante il combattimento in questo turno puoi spendere un qualsiasi ammontare di punti Movimento: 1 per ottenere Attacco 1 e/o 2 per ottenere Attacco a Distanza 1.", 6)
aa("refreshing_walk", "base", "green", "Passeggiata Rigenerante", "Refreshing Walk",
   [MV(2), ["if", "not_combat", [HEAL(1)]]], [MV(4), ["if", "not_combat", [HEAL(2)]]],
   "Movimento 2 e Cura 1. Se giocata durante il combattimento, soltanto Movimento 2.",
   "Movimento 4 e Cura 2. Se giocata durante il combattimento, soltanto Movimento 4.", 7)
aa("intimidate", "base", "red", "Intimidire", "Intimidate",
   [ch([INF(4)], [ATT(3)]), ["rep", -1]], [ch([INF(8)], [ATT(7)]), ["rep", -2]],
   "Influenza 4 o Attacco 3. Reputazione -1", "Influenza 8 o Attacco 7. Reputazione -2", 8,
   note="La perdita di Reputazione si applica in entrambi i casi.")
aa("frost_bridge", "base", "blue", "Ponte Ghiacciato", "Frost Bridge",
   [MV(2), ["terrain", {"swamp": 1}]], [MV(4), ["terrain", {"lake": 1, "swamp": 1}]],
   "Movimento 2. Il costo di Movimento nelle paludi viene ridotto a 1 in questo turno.",
   "Movimento 4. Puoi attraversare i laghi, e il costo di Movimento nei laghi e nelle paludi viene ridotto a 1 in questo turno.", 9,
   note="I laghi resi attraversabili non diventano spazi sicuri: non puoi terminarvi il turno.")
aa("song_of_wind", "base", "white", "Canto del Vento", "Song of Wind",
   [MV(2), ["terrain", {"plains": "-1", "desert": "-1", "wasteland": "-1", "min": 0}]],
   [MV(2), ["terrain", {"plains": "-2", "desert": "-2", "wasteland": "-2", "min": 0}],
    OPT(["pay_mana", "blue", [["terrain", {"lake": 0}]]])],
   "Movimento 2. Il costo di Movimento in pianura, nei deserti e nelle terre perdute viene ridotto di 1, fino ad un minimo di 0 in questo turno.",
   "Movimento 2. Il costo di Movimento in pianura, nei deserti e nelle terre perdute viene ridotto di 2, fino ad un minimo di 0. Puoi pagare un mana blu per attraversare i laghi con costo di Movimento pari a 0 in questo turno.", 10,
   note="I laghi resi attraversabili non diventano spazi sicuri.")
aa("path_finding", "base", "green", "Esploratore", "Path Finding",
   [MV(2), ["terrain", {"all": "-1", "min": 2}]], [MV(4), ["terrain", {"all": "<=2"}]],
   "Movimento 2. Il costo di Movimento su tutti i terreni viene ridotto di 1, fino ad un minimo di 2, questo turno.",
   "Movimento 4. Il costo di Movimento su tutti i terreni viene ridotto a 2 in questo turno.", 11,
   note="'Tutti i terreni' = terreni attraversabili; laghi e montagne restano invalicabili.")
aa("blood_ritual", "base", "red", "Rituale di Sangue", "Blood Ritual",
   [sp("take_wound"), CRY("red"), ANY_TOKEN],
   [sp("take_wound"), ANY_TOKEN, ANY_TOKEN, ANY_TOKEN, OPT(["pay_mana", "basic", [CRY("$paid")]])],
   "Subisci una Ferita. Guadagni un cristallo di mana rosso nel tuo Inventario e un segnalino mana di un colore qualsiasi (inclusi quelli non base).",
   "Subisci una Ferita. Guadagni tre segnalini mana di qualsiasi colore (inclusi quelli non base). Puoi pagare un mana di un colore base per guadagnare un cristallo di quel colore nel tuo Inventario.", 12,
   note="La Ferita va in mano (in combattimento conta per il Colpo di Grazia).")
aa("pure_magic", "base", "blue", "Magia Pura", "Pure Magic",
   [ch([["pay_mana", "green", [MV(4)]]], [["pay_mana", "white", [INF(4)]]], [["pay_mana", "blue", [BLK(4)]]], [["pay_mana", "red", [ATT(4)]]])],
   [ch([["pay_mana", "green", [MV(7)]]], [["pay_mana", "white", [INF(7)]]], [["pay_mana", "blue", [BLK(7)]]], [["pay_mana", "red", [ATT(7)]]])],
   "Quando giochi questa carta, paga un mana. Se hai pagato un mana verde, hai Movimento 4. Se hai pagato un mana bianco, hai Influenza 4. Se hai pagato un mana blu, hai Blocco 4. Se hai pagato un mana rosso, hai Attacco 4.",
   "Quando giochi questa carta, paga un mana. Se hai pagato un mana verde, hai Movimento 7. Se hai pagato un mana bianco, hai Influenza 7. Se hai pagato un mana blu, hai Blocco 7. Se hai pagato un mana rosso, hai Attacco 7.", 13,
   note="Il mana dell'effetto è in aggiunta al mana blu che potenzia la carta. Di Giorno l'oro vale come uno qualsiasi dei 4 colori.")
aa("heroic_tale", "base", "white", "Racconto Eroico", "Heroic Tale",
   [INF(3), md("per_recruit", rep=1)], [INF(6), md("per_recruit", fame=1, rep=1)],
   "Influenza 3. Per ogni Unità che recluti in questo turno, ricevi Reputazione +1.",
   "Influenza 6. Per ogni Unità che recluti in questo turno, ricevi Fama +1 e Reputazione +1.", 14)
aa("regeneration", "base", "green", "Rigenerazione", "Regeneration",
   [HEAL(1), ["ready_unit", 2]], [HEAL(2), ["ready_unit", 3]],
   "Cura 1. Rendi pronta un'Unità di Livello I o II che controlli.",
   "Cura 2. Rendi pronta un'Unità di Livello I, II o III che controlli.", 15,
   note="Cura non utilizzabile in combattimento (rendere pronta un'Unità sì).")
aa("into_the_heat", "base", "red", "Nella Mischia", "Into the Heat",
   [md("units_bonus", attack=2, block=2, no_unit_damage=True)], [md("units_bonus", attack=3, block=3, no_unit_damage=True)],
   "Gioca questa carta all'inizio del combattimento. A tutte le tue Unità viene aumentato di 2 il valore di Attacco e di Blocco in questo combattimento. Non puoi assegnare danno alle tue Unità in questo turno.",
   "Gioca questa carta all'inizio del combattimento. A tutte le tue Unità viene aumentato di 3 il valore di Attacco e di Blocco in questo combattimento. Non puoi assegnare danno alle tue Unità in questo turno.", 16,
   combat_only=True, note="Solo all'inizio del combattimento (prima della fase Attacco a distanza e d'assedio).")
aa("steady_tempo", "base", "blue", "Tempo Stabile", "Steady Tempo",
   [MV(2), md("card_to_deck_end_turn", pos="bottom")], [MV(4), md("card_to_deck_end_turn", pos="top")],
   "Movimento 2. Alla fine del tuo turno, anziché mettere questa carta nella tua pila degli scarti, puoi piazzarla in fondo al tuo mazzo Impresa a meno che non sia vuoto.",
   "Movimento 4. Alla fine del tuo turno, anziché mettere questa carta nella tua pila degli scarti, puoi piazzarla in cima al tuo mazzo Impresa.", 17)
aa("diplomacy", "base", "white", "Diplomazia", "Diplomacy",
   [INF(2), md("influence_as_block", elem="phys")],
   [INF(4), ch([md("influence_as_block", elem="ice")], [md("influence_as_block", elem="fire")])],
   "Influenza 2. Puoi usare Influenza come Blocco in questo turno.",
   "Influenza 4. Scegli Ghiaccio o Fuoco. Puoi usare Influenza come Blocco per l'elemento scelto in questo turno.", 18)
aa("in_need", "base", "green", "Nel Bisogno", "In Need",
   [INF(3), sp("influence_per_wound", n=1)], [INF(5), sp("influence_per_wound", n=2)],
   "Influenza 3. Ricevi 1 punto Influenza addizionale per ogni carta Ferita nella tua mano o su Unità che controlli.",
   "Influenza 5. Ricevi 2 punti Influenza addizionali per ogni carta Ferita nella tua mano o su Unità che controlli.", 19)
aa("decompose", "base", "red", "Decomporre", "Decompose",
   [sp("throw_action", by_color={c: [CRY(c), CRY(c)] for c in BASIC4})],
   [sp("throw_action", by_color={c: [CRY(o) for o in BASIC4 if o != c] for c in BASIC4})],
   "Quando giochi questa carta, getta via dalla tua mano una carta Azione. Guadagni due cristalli nel tuo Inventario dello stesso colore della carta gettata.",
   "Quando giochi questa carta, getta via una carta Azione dalla tua mano. Guadagni un cristallo nel tuo Inventario di ciascun colore base che non sia del colore della carta gettata.", 20)
aa("crystal_mastery", "base", "blue", "Maestria del Cristallo", "Crystal Mastery",
   [sp("crystal_copy")], [md("crystals_return")],
   "Guadagni un cristallo nel tuo Inventario dello stesso colore di un cristallo che già possiedi.",
   "Alla fine del turno, qualsiasi cristallo tu abbia speso in questo turno ritorna nel tuo Inventario.", 21)
aa("mana_storm", "base", "white", "Tempesta di Mana", "Mana Storm",
   [sp("crystal_from_source_die", reroll=True)], [sp("reroll_source"), ["extra_die", 3], md("source_black_gold_any")],
   "Scegli un dado mana nella Riserva che mostri un colore base. Guadagni un cristallo di quel colore nel tuo Inventario, dopodiché ritira immediatamente quel dado e rimettilo nella Riserva.",
   "Ritira tutti i dadi nella Riserva. Puoi utilizzare tre dadi extra dalla Riserva, e puoi utilizzare dadi che mostrano il nero o l'oro come mana di qualsiasi colore base, a prescindere dal Round.", 22)
aa("ambush", "base", "green", "Imboscata", "Ambush",
   [MV(2), md("first_attack_or_block_bonus", attack=1, block=2)], [MV(4), md("first_attack_or_block_bonus", attack=2, block=4)],
   "Movimento 2. Aggiungi +1 alla tua prima carta Attacco di qualsiasi tipo oppure +2 alla tua prima carta Blocco di qualsiasi tipo, a quella che giochi prima in questo turno.",
   "Movimento 4. Aggiungi +2 alla tua prima carta Attacco di qualsiasi tipo oppure +4 alla tua prima carta Blocco di qualsiasi tipo, a quella che giochi prima in questo turno.", 23)
aa("maximal_effect", "base", "red", "Effetto Massimo", "Maximal Effect",
   [sp("maximal_effect", mode="basic", times=3)], [sp("maximal_effect", mode="powered", times=2)],
   "Quando giochi questa carta, getta via un'altra carta Azione dalla tua mano. Usa l'effetto base di quella carta tre volte.",
   "Quando giochi questa carta, getta via un'altra carta Azione dalla tua mano. Usa l'effetto più potente di quella carta due volte (gratuitamente).", 24,
   note="Effetto 'composto': conta come un unico effetto (es. con Determinazione puoi bloccare attacchi diversi).")
aa("magic_talent", "base", "blue", "Talento Magico", "Magic Talent",
   [sp("magic_talent")], [["pay_mana", "basic", [sp("gain_from_offer", offer="spells", color="$paid", to="discard")]]],
   "Scarta una carta dalla tua mano. Puoi giocare una carta Incantesimo dello stesso colore presente nell'offerta degli Incantesimi in questo turno come se fosse nella tua mano. Quella carta rimane nell'offerta degli Incantesimi.",
   "Quando giochi questa carta, paga un mana di un colore qualsiasi. Guadagni una carta Incantesimo di quel colore dall'offerta degli Incantesimi e mettila nella tua pila degli scarti.", 25)
aa("learning", "base", "white", "Imparare", "Learning",
   [INF(2), md("buy_aa_with_influence", cost=6, to="discard")], [INF(4), md("buy_aa_with_influence", cost=9, to="hand")],
   "Influenza 2. Una volta durante questo turno, puoi pagare Influenza 6 per guadagnare una carta Azione Avanzata dall'offerta delle Azioni Avanzate e metterla nella tua pila degli scarti.",
   "Influenza 4. Una volta durante questo turno, puoi pagare Influenza 9 per guadagnare una carta Azione Avanzata dall'offerta delle Azioni Avanzate e metterla nella tua mano.", 26)
aa("training", "base", "green", "Allenarsi", "Training",
   [sp("throw_action", by_color={c: [sp("gain_from_offer", offer="aa", color=c, to="discard")] for c in BASIC4})],
   [sp("throw_action", by_color={c: [sp("gain_from_offer", offer="aa", color=c, to="hand")] for c in BASIC4})],
   "Getta via una carta Azione dalla tua mano, quindi prendi una carta dello stesso colore dall'offerta delle Azioni Avanzate e mettila nella tua pila degli scarti.",
   "Getta via una carta Azione dalla tua mano, quindi prendi una carta dello stesso colore dall'offerta delle Azioni Avanzate e aggiungila alla tua mano.", 27)

# --- Lost Legion (12): carte 287-298/377
aa("counterattack", "ll", "red", "Contrattacco", "Counterattack",
   [ATT(2), sp("attack_per_blocked", n=2)], [ATT(4), sp("attack_per_blocked", n=3)],
   "Attacco 2. Ottieni un Attacco 2 addizionale per ogni nemico bloccato in questo turno.",
   "Attacco 4. Ottieni un Attacco 3 addizionale per ogni nemico bloccato in questo turno.", 28, combat_only=True,
   note="Utile nella fase Attacco: conta i nemici bloccati con successo in questo combattimento.")
aa("ritual_attack", "ll", "red", "Attacco Rituale", "Ritual Attack",
   [sp("throw_action", by_color={"red": [ATT(5)], "blue": [ATT(3, "ice")], "white": [RNG(3)], "green": [SIE(2)]})],
   [sp("throw_action", by_color={"red": [ATT(6, "fire")], "blue": [ATT(4, "cold")], "white": [RNG(4, "fire")], "green": [SIE(3, "fire")]})],
   "Getta via un'altra carta azione. A seconda del suo colore, ottieni: Attacco 5 se rossa, Attacco di Ghiaccio 3 se blu, Attacco a Distanza 3 se bianca, Attacco d'Assedio 2 se verde.",
   "Getta via un'altra carta azione. A seconda del suo colore, ottieni: Attacco di Fuoco 6 se rossa, Attacco di Fuoco Freddo 4 se blu, Attacco di Fuoco a Distanza 4 se bianca, Attacco di Fuoco d'Assedio 3 se verde.", 29,
   combat_only=True)
aa("blood_of_ancients", "ll", "red", "Sangue degli Antichi", "Blood of Ancients",
   [sp("take_wound"), ["pay_mana", "basic", [sp("gain_from_offer", offer="aa", color="$paid", to="hand")]]],
   [sp("take_wound", to="hand_or_discard"), sp("use_offer_card", offer="aa", mode="powered", free=True)],
   "Guadagni una Ferita. Paga un mana di un colore qualsiasi. Guadagni una carta di quel colore dall'offerta delle Azioni Avanzate e aggiungila alla tua mano.",
   "Guadagni una Ferita nella tua mano o nella tua pila degli scarti. Utilizza l'effetto più forte di qualsiasi carta dall'offerta delle Azioni Avanzate senza pagarne il suo costo in mana. La carta rimane nell'offerta.", 30)
aa("shield_bash", "ll", "blue", "Colpo di Scudo", "Shield Bash",
   [sp("block_vs_swift", n=3, n_if_swift=6)], [sp("block_vs_swift", n=5, n_if_swift=10, armor_excess=True)],
   "Blocco 3. Conta doppio contro un attacco con Rapidità.",
   "Blocco 5. Conta doppio contro un attacco con Rapidità. Il nemico Bloccato subisce Armatura -1 per ogni punto di blocco più alto del necessario (fino ad un minimo di 1).", 31,
   combat_only=True, note="La riduzione d'Armatura è un effetto non-Attacco di carta blu." + ICE_RES)
aa("temporal_portal", "ll", "blue", "Portale Temporale", "Temporal Portal",
   [sp("use_as_action"), sp("safe_move", spaces=1), md("hand_limit_next", any=1)],
   [ch([sp("use_as_action"), sp("safe_move", spaces=2), md("hand_limit_next", any=1)],
       [sp("use_as_action"), sp("safe_move", spaces=1), md("hand_limit_next", any=2)])],
   "Giocala come tua azione in questo turno. Puoi muovere in uno spazio sicuro rivelato adiacente (senza provocare mostri infuriati). Che tu ti muova o meno, il tuo limite di carte in Mano è più alto di 1 la prossima volta che pescherai carte.",
   "Come sopra, tranne che puoi muovere di due spazi anziché uno in uno spazio sicuro rivelato, oppure il tuo limite di carte in Mano è aumentato di 2 anziché di 1.", 32)
aa("spell_forge", "ll", "blue", "Forgia di Incantesimi", "Spell Forge",
   [sp("crystal_from_offer", offer="spells", n=1)], [sp("crystal_from_offer", offer="spells", n=2)],
   "Guadagni un cristallo nel tuo Inventario dello stesso colore di una delle carte Incantesimo nell'offerta Incantesimi.",
   "Guadagni due cristalli nel tuo Inventario dello stesso colore di due differenti carte Incantesimo nell'offerta Incantesimi.", 33)
aa("chivalry", "ll", "white", "Cavalleria", "Chivalry",
   [ch([ATT(3)], [sp("attack_with_kill_reward", n=2, rep=1)])],
   [ch([ATT(6)], [sp("attack_with_kill_reward", n=4, rep=1, fame=1)])],
   "Attacco 3, oppure Attacco 2 e Reputazione +1 per ogni nemico sconfitto da questo attacco.",
   "Attacco 6, oppure Attacco 4 e Reputazione +1 e Fama +1 per ogni nemico sconfitto da questo attacco.", 34, combat_only=True)
aa("peaceful_moment", "ll", "white", "Momento di Pace", "Peaceful Moment",
   [INF(3), OPT(sp("use_as_action"), md("influence_to_heal", per=2))],
   [INF(6), OPT(sp("use_as_action"), md("influence_to_heal", per=2), md("ready_units_for_influence", per_level=2, max_level=4))],
   "Influenza 3. Puoi giocarla come tua azione del turno: se lo fai, puoi ottenere Cura 1 per ogni 2 punti di Influenza che spendi.",
   "Influenza 6. Puoi giocarla come tua azione del turno: se lo fai, puoi ottenere Cura 1 per ogni 2 punti di Influenza che spendi e/o rendi pronta una Unità pagando 2 punti Influenza per livello dell'Unità.", 35,
   note="Se giocata come azione non puoi fare altre azioni (combattimento, interazione) in questo turno.")
aa("dodge_and_weave", "ll", "white", "Schiva e Fuggi", "Dodge and Weave",
   [sp("reduce_enemy_attack", n=2), md("attack_if_no_wounds", n=1)],
   [ch([sp("reduce_enemy_attack", n=4)], [sp("reduce_enemy_attack", n=2, attacks=2)]), md("attack_if_no_wounds", n=2)],
   "Riduci di 2 un attacco nemico. Guadagni Attacco 1 nella fase Attacco se non hai aggiunto Ferite alla tua mano nelle fasi combattimento precedenti.",
   "Riduci di 4 un attacco nemico oppure di 2 due attacchi di uno o di due nemici. Guadagni Attacco 2 nella fase Attacco se non hai aggiunto Ferite alla tua mano nelle fasi combattimento precedenti.", 36,
   combat_only=True, note="Si gioca nella fase di Blocco.")
aa("stout_resolve", "ll", "green", "Risoluzione Decisa", "Stout Resolve",
   [sp("stout_resolve", n=2, per=1, max_cards=1, max_wounds=1, wounds_only=True)],
   [sp("stout_resolve", n=3, per=2, max_cards=99, max_wounds=1, wounds_only=False)],
   "Movimento 2, Influenza 2, Attacco 2 o Blocco 2. Puoi scartare una Ferita per aumentare l'effetto di 1.",
   "Movimento 3, Influenza 3, Attacco 3 o Blocco 3. Puoi scartare un qualsiasi numero di carte, inclusa una Ferita, per aumentare l'effetto di 2 per ciascuna di esse.", 37)
aa("force_of_nature", "ll", "green", "Forza della Natura", "Force of Nature",
   [sp("unit_resist", elem="phys")], [ch([SIE(3)], [BLK(6)])],
   "L'Unità scelta guadagna Resistenza fisica in questo combattimento.", "Attacco d'Assedio 3 o Blocco 6.", 38, combat_only=True)
aa("mountain_lore", "ll", "green", "Conoscere la Montagna", "Mountain Lore",
   [MV(3), md("hand_limit_next", hills=1)],
   [MV(5), ["terrain", {"mountain": 5, "safe": ["mountain"]}], md("hand_limit_next", hills=1, mountain=2)],
   "Movimento 3. Se termini il tuo turno sulle colline, il tuo limite di carte in Mano è aumentato di 1 la prossima volta che peschi delle carte.",
   "Movimento 5. Puoi entrare nelle montagne al costo di Movimento 5 e sono considerate uno spazio sicuro per te alla fine di questo turno. Se termini il tuo turno sulle montagne/colline, il tuo limite di carte in Mano è aumentato di 2/1 la prossima volta che peschi delle carte.", 39)

# --- Ultimate Edition (4 bicolori): carte UE266-269/377
aa("power_of_crystals", "ue", "green", "Potere dei Cristalli", "Power of Crystals",
   [sp("crystal_new_color")],
   [ch([MV(4)], [HEAL(2)], [["draw", 2]]), sp("repeat_per_crystal_set", effects=[ch([MV(2)], [HEAL(1)], [["draw", 1]])])],
   "Guadagni un cristallo per il tuo Inventario di un colore base che ancora non possiedi.",
   "Movimento 4, oppure Cura 2, oppure pesca due carte. Per ogni set di quattro cristalli di colore differente nel tuo Inventario: Movimento 2, oppure Cura 1, oppure pesca una carta.", 40,
   colors=["green", "blue"], note="Bicolore verde/blu: si potenzia con mana verde o blu.")
aa("explosive_bolt", "ue", "white", "Fulmine Esplosivo", "Explosive Bolt",
   [sp("take_wound"), CRY("white"), CRY("red")], [sp("attack_with_kill_reward", n=3, kind="ranged", armor_minus_other=1)],
   "Prendi una Ferita. Guadagni un cristallo bianco e uno rosso per il tuo Inventario.",
   "Attacco a Distanza 3. Per ogni nemico sconfitto da questo attacco, un altro nemico subisce Armatura -1 (fino a un minimo di 1).", 41,
   colors=["white", "red"], note="Bicolore bianco/rosso." + FIRE_RES + " (la riduzione d'Armatura è un effetto non-Attacco).")
aa("rush_of_adrenaline", "ue", "red", "Scarica di Adrenalina", "Rush of Adrenaline",
   [md("draw_on_wound", n=3)], [md("draw_on_wound", n=3, throw_first=True)],
   "Per ognuna delle prime tre Ferite che prendi alla tua mano in questo turno, pesca una carta.",
   "Dopo aver preso la prima Ferita alla tua mano in questo turno, gettala via e pesca una carta. Per ognuna delle tre prossime Ferite che prendi, pesca una carta.", 42,
   colors=["red", "green"], note="Bicolore rosso/verde. Le Ferite già prese in questo turno prima di giocarla contano (si pesca subito).")
aa("chilling_stare", "ue", "blue", "Sguardo Gelido", "Chilling Stare",
   [ch([INF(3)], [sp("enemy_attack_strip", what="abilities")])], [ch([INF(5)], [sp("enemy_no_attack")])],
   "Influenza 3, oppure l'attacco di un nemico a scelta perde tutte le abilità d'attacco (ma non il suo colore).",
   "Influenza 5, oppure un nemico a scelta non attacca in questo turno.", 43,
   colors=["blue", "white"], note="Bicolore blu/bianco. Le opzioni sul nemico si usano in combattimento (fase di Blocco)." + ICE_RES)

# ============================================================== ADVANCED ACTIONS (fan: Rise of the Forgemaster)
def rf(id, color, name_it, name_en, basic, powered, tb, tp, idx, impl=True, note="", te=None, **kw):
    n = "Campagna fan 'Rise of the Forgemaster'." + (" " + note if note else "")
    return card("rotf_" + id, set="fan", type="aa", color=color, name_it=name_it, name_en=name_en, basic=basic,
                powered=powered, t_basic=tb, t_powered=tp, src=(S_ROTF, idx), impl=impl, note=n, text_en=te, **kw)

SH = "frammento di mana"
NOSH = "Usa meccaniche di RotF non presenti nel gioco (frammenti di mana / Pozioni / 'tuck' / 'prepare' / veleno / icona pugnale)."
rf("abrupt_emanation", "red", "Emanazione Improvvisa", "Abrupt Emanation",
   [ch([MANA("green"), MANA("white")], [MANA("red"), MANA("blue")])],
   [sp("pay_crystal", effects=[sp("use_offer_card", offer="spells", mode="basic", color="$paid", free=True)])],
   "Guadagni due segnalini mana: verde e bianco, oppure rosso e blu.",
   "Quando giochi questa carta, paga un cristallo. Se lo fai, usa l'effetto base di un Incantesimo dello stesso colore dall'offerta degli Incantesimi senza pagarne il costo in mana.", 0,
   te=("Gain two mana tokens - either green and white, or red and blue.", "When you play this, pay a crystal. If you do, use the basic effect of a Spell of the same color from the Spells offer without paying its mana cost."))
rf("magic_talent", "blue", "Talento Magico (RotF)", "Magic Talent (RotF)",
   [sp("magic_talent", variant="basic_pay")],
   [sp("pay_crystal", effects=[sp("gain_from_offer", offer="spells", color="$paid", to="discard")])],
   "Scarta una carta di qualsiasi colore. Usa l'effetto base di un Incantesimo dello stesso colore dall'offerta degli Incantesimi pagandone il costo in mana.",
   "Paga un cristallo di qualsiasi colore. Se lo fai, guadagni un Incantesimo di quel colore dall'offerta degli Incantesimi e mettilo nella tua pila degli scarti.", 1,
   te=("Discard a card of any color. Use the basic effect of a Spell of the same color from the Spells Offer by paying its mana cost.", "Pay a crystal of any color. If you do, gain a Spell of that color from the Spells Offer and put it in your discard pile."))
rf("extemporization", "white", "Estemporaneità", "Extemporization",
   [sp("pay_crystal", by_color={"green": [SIE(3)], "white": [RNG(4)], "blue": [RNG(3, "ice")], "red": [RNG(3, "fire")]})],
   [sp("discard_card", wound_ok=True, effects=[ch([MV(6)], [INF(6)], [ATT(6)], [BLK(6)])])],
   "Paga un cristallo di qualsiasi colore. Se hai pagato verde, Attacco d'Assedio 3. Se hai pagato bianco, Attacco a Distanza 4. Se hai pagato blu, Attacco di Ghiaccio a Distanza 3. Se hai pagato rosso, Attacco di Fuoco a Distanza 3.",
   "Scarta un'altra carta dalla tua mano (anche una Ferita) per ottenere Movimento 6, Influenza 6, Attacco 6 o Blocco 6.", 2,
   te=("Pay a crystal of any color. If you paid green, Siege Attack 3. If you paid white, Ranged Attack 4. If you paid blue, Ranged Ice Attack 3. If you paid red, Ranged Fire Attack 3.", "Discard another card from your hand (even a Wound) to get Move 6, Influence 6, Attack 6 or Block 6."))
rf("ambush", "green", "Imboscata (RotF)", "Ambush (RotF)",
   [MV(3), md("no_provoke")], [MV(5), md("no_provoke"), md("first_attack_or_block_bonus", attack=2)],
   "Movimento 3. Il tuo Movimento non provoca i nemici infuriati in questo turno.",
   "Come l'effetto base, ma con Movimento 5. (Durata) Aggiungi un bonus di +2 all'Attacco della prossima carta che giochi in questo turno.", 3,
   te=("Move 3. Your Move does not provoke rampaging enemies this turn.", "Same as the basic effect, but with Move 5. Add +2 bonus to Attack for the next card you play this turn."))
rf("raving_prophecies", "red", "Profezie Deliranti", "Raving Prophecies",
   [ch([INF(3)], [sp("rotf_mana_shard", color="red")], [sp("take_wound", n=2, to="discard"), ["draw", 3]])],
   [sp("take_wound"), sp("gain_from_offer", offer="aa", color="lowest", to="hand"), ["rep", -1]],
   f"Influenza 3, guadagni un {SH} rosso, oppure guadagni 2 Ferite nella tua pila degli scarti per pescare 3 carte.",
   "Guadagni una Ferita. Guadagni la carta nella posizione più bassa dell'offerta delle Azioni Avanzate e mettila nella tua mano. Reputazione -1.", 4,
   impl=False, note=NOSH,
   te=("Influence 3, gain a red mana shard, or gain 2 Wounds to your discard pile to draw 3 cards.", "Gain a Wound. Gain the card from the lowest position on the Advanced Actions offer, and put into your hand. Reputation -1."))
rf("steady_tempo", "blue", "Ritmo Costante", "Steady Tempo (RotF)",
   [MV(3), sp("rotf_tuck", card="self")], [MV(4), sp("rotf_prepare", card="self")],
   "Movimento 3. Puoi accantonare ('tuck') questa carta.", "Movimento 4. Puoi preparare ('prepare') questa carta.", 5,
   impl=False, note=NOSH, te=("Move 3. You may tuck this card.", "Move 4. You may prepare this card."))
rf("dodge_and_weave", "white", "Schiva e Fuggi (RotF)", "Dodge and Weave (RotF)",
   [sp("reduce_enemy_attack", n=2), md("attack_if_no_wounds", n=1)],
   [ch([sp("reduce_enemy_attack", n=4)], [sp("reduce_enemy_attack", n=2, attacks=2)]), md("attack_if_no_wounds", n=2)],
   "Riduci di 2 un attacco nemico. (Durata) Guadagni Attacco 1 nella fase Attacco se non hai aggiunto Ferite alla tua mano nelle fasi di combattimento precedenti.",
   "Riduci di 4 un attacco nemico, oppure di 2 due attacchi di uno o due nemici. (Durata) Guadagni Attacco 2 nella fase Attacco se non hai aggiunto Ferite alla tua mano nelle fasi di combattimento precedenti.", 6,
   combat_only=True, note="Uguale alla carta ufficiale.",
   te=("Reduce one enemy attack by 2. Gain Attack 1 in the Attack phase if you did not add any Wounds to your hand in the previous combat phases.", "Reduce one enemy attack by 4, or two attacks of one or two enemies by 2. Gain Attack 2 in the Attack phase if you did not add any Wounds to your hand in the previous combat phases."))
rf("diligence", "green", "Diligenza", "Diligence",
   [INF(2), md("deed_discount", n=1, cards=3)],
   [ch([sp("play_with_bonus", bonus=3)], [sp("rotf_mana_shard", color="$card")])],
   "Influenza 2. Ottieni uno sconto di 1 sul costo delle prossime tre carte Impresa che acquisti durante un'Interazione.",
   f"Gioca un'altra carta Azione dalla tua mano con un bonus di +3. Puoi usarne l'effetto più forte come se fosse stata potenziata dal mana, oppure guadagni un {SH} dello stesso colore.", 7,
   impl=False, note=NOSH + " Nel Lua è scritta 'Deligence'.",
   te=("Influence 2. Get a discount of 1 towards the costs of the next three Deed cards you buy during Interaction.", "Play another Action card from your hand with a +3 bonus. You may use its stronger effect as if it was powered by mana, or gain a mana shard of the same color."))
rf("bloodlust", "red", "Sete di Sangue", "Bloodlust",
   [ch([ATT(2)], [BLK(2)]), OPT(sp("take_wound"), sp("boost_this", n=1), sp("rotf_mana_shard", color="red"))],
   [ch([ATT(3, "fire")], [BLK(3, "fire")]), OPT(sp("discard_wounds_bonus", max=1, per=2))],
   f"Attacco o Blocco 2. Puoi subire una Ferita per aumentarlo a 3 e guadagnare un {SH} rosso.",
   "Attacco di Fuoco o Blocco di Fuoco 3. Puoi scartare una Ferita per aumentarlo a 5.", 8,
   impl=False, combat_only=True, note=NOSH,
   te=("Attack or Block 2. You may take a Wound to increase this to 3, and to gain a red mana shard.", "Fire Attack or Fire Block 3. You may discard a Wound to increase this to 5."))
rf("treasure_hunt", "blue", "Caccia al Tesoro", "Treasure Hunt",
   [MV(3), md("rotf_lake_reward", near=1, shard="blue")],
   [MV(5), ["terrain", {"lake": 2, "safe": ["lake"]}], md("rotf_lake_reward", near=0, crystal="basic")],
   f"Movimento 3. Se termini la fase di movimento entro uno spazio da un lago, guadagni un {SH} blu.",
   "Movimento 5. Puoi entrare nei laghi al costo di Movimento 2 e sono considerati spazi sicuri per te alla fine di questo turno. Se termini la fase di movimento in un lago, guadagni un cristallo di qualsiasi colore nel tuo Inventario.", 9,
   impl=False, note=NOSH,
   te=("Move 3. If you end your move phase within one space of lakes, gain a blue mana shard.", "Move 5. You can enter lakes at a Move cost of 2 and they are considered a safe space for you at the end of this turn. If you end your move phase in lakes, gain a crystal of any color to your Inventory."))
rf("shrewdness", "white", "Scaltrezza", "Shrewdness",
   [ch([INF(3)], [sp("rotf_mana_shard", color="white")], [["extra_die", 2]])], [INF(7)],
   f"Influenza 3, guadagni un {SH} bianco, oppure puoi usare due dadi mana addizionali dalla Riserva in questo turno.",
   "Influenza 7", 10, impl=False, note=NOSH,
   te=("Influence 3, gain a white mana shard, or you can use two additional mana dice from the Source this turn.", "Influence 7"))
rf("herbalism", "green", "Erboristeria", "Herbalism",
   [sp("heal_unit_ready", max_level=2, then=[sp("rotf_mana_shard", color="green")])],
   [sp("heal_unit_ready", max_level=3, then=[]), sp("throw_wound_from_discard", then=[md("hand_limit_next", any=1)])],
   f"Guarisci un'Unità di Livello I o II. Se lo fai, rendi pronta quell'Unità e guadagni un {SH} verde.",
   "Guarisci un'Unità di Livello I, II o III. Se lo fai, rendi pronta quell'Unità. Getta via una Ferita dalla tua pila degli scarti. Se lo fai, il tuo limite di carte in Mano è più alto di 1 la prossima volta che peschi.", 11,
   impl=False, note=NOSH,
   te=("Heal a level I or II Unit. If you do, ready that Unit and gain a green mana shard.", "Heal a level I, II or III Unit. If you do, ready that Unit. Throw away a Wound from your discard pile. If you do, your Hand limit is higher by 1 the next time you draw cards."))
for i, (cid, col, nit, nen, o1, o2) in enumerate([
        ("flame_forge", "red", "Forgia della Fiamma", "Flame Forge", "green", "white"),
        ("frost_forge", "blue", "Forgia del Gelo", "Frost Forge", "green", "white"),
        ("storm_forge", "white", "Forgia della Tempesta", "Storm Forge", "red", "blue"),
        ("earth_forge", "green", "Forgia della Terra", "Earth Forge", "red", "blue")]):
    ci = {"red": "rosso", "blue": "blu", "white": "bianco", "green": "verde"}
    rf(cid, col, nit, nen, [MANA(col), MANA("black"), sp("rotf_mana_shard", color=col)],
       [sp("rotf_mana_shard", color=o1), sp("rotf_mana_shard", color=o2), CRY(col)],
       f"Guadagni un segnalino mana {ci[col]} e uno nero, e un {SH} {ci[col]}.",
       f"Guadagni un {SH} {ci[o1]} e uno {ci[o2]}, e un cristallo {ci[col]} nel tuo Inventario.", 12 + i,
       impl=False, note=NOSH,
       te=(f"Gain one {col} and one black mana token, and a {col} mana shard.", f"Gain one {o1} and one {o2} mana shard, and a {col} crystal to your Inventory."))
rf("rush_of_adrenaline", "red", "Scarica di Adrenalina (RotF)", "Rush of Adrenaline (RotF)",
   [md("prevent_next_wound", draw=2)], [ATT(4), sp("discard_wounds_bonus", max=2, per=3)],
   "(Durata) La prossima volta che guadagneresti una Ferita alla tua mano in questo turno, previeni quella Ferita e qualsiasi effetto aggiuntivo derivante da essa, e pesca 2 carte.",
   "Attacco 4. Puoi scartare fino a 2 carte Ferita per aumentare questo Attacco di 3 per ciascuna.", 16,
   colors=["red", "green"], note="Bicolore rosso/verde.",
   te=("The next time you would gain a Wound to your hand this turn, prevent that Wound and any additional effects from it, and draw 2 cards.", "Attack 4. You may discard up to 2 Wound cards to increase this Attack by 3 for each."))
rf("chilling_stare", "blue", "Sguardo Gelido (RotF)", "Chilling Stare (RotF)",
   [ch([INF(3)], [sp("enemy_attack_strip", what="abilities")])], [ch([INF(5)], [sp("enemy_no_attack", unfortified=True)])],
   "Influenza 3, oppure l'attacco di un nemico a scelta perde tutte le abilità d'attacco (ma non il suo colore).",
   "Influenza 5, oppure un nemico bersaglio non fortificato non attacca in questo combattimento.", 17,
   colors=["blue", "white"], note="Bicolore blu/bianco. Icona: i nemici con Resistenza al Ghiaccio ignorano l'effetto." ,
   te=("Influence 3, or a chosen enemy attack loses all attack abilities (but not its color).", "Influence 5, or target unfortified enemy does not attack this combat."))
rf("explosive_bolt", "white", "Fulmine Esplosivo (RotF)", "Explosive Bolt (RotF)",
   [sp("rotf_mana_shard", color="white"), sp("rotf_mana_shard", color="red")],
   [sp("attack_with_kill_reward", n=3, kind="ranged", armor_minus_other=1)],
   f"Guadagni un {SH} bianco e uno rosso.",
   "Attacco a Distanza 3. Per ogni nemico sconfitto da questo attacco, un altro nemico subisce Armatura -1 (fino a un minimo di 1).", 18,
   impl=False, colors=["white", "red"], note="Bicolore bianco/rosso. " + NOSH,
   te=("Gain a white and a red mana shard.", "Ranged Attack 3. For each enemy defeated by this attack, another enemy gets Armor -1 (to a minimum of 1)."))
rf("power_of_crystals", "green", "Potere dei Cristalli (RotF)", "Power of Crystals (RotF)",
   [sp("rotf_mana_shard", color="green"), sp("rotf_mana_shard", color="blue")],
   [ch([MV(4)], [HEAL(2)], [["draw", 2]]), sp("repeat_per_crystal_set", effects=[ch([MV(2)], [HEAL(1)], [["draw", 1]])])],
   f"Guadagni un {SH} verde e uno blu.",
   "Movimento 4, oppure Cura 2, oppure pesca due carte. Per ogni set di quattro cristalli di colore differente nel tuo Inventario: Movimento 2, oppure Cura 1, oppure pesca una carta.", 19,
   impl=False, colors=["green", "blue"], note="Bicolore verde/blu. " + NOSH,
   te=("Gain a green and a blue mana shard.", "Move 4, or Heal 2, or draw two cards. For each set of four different color crystals in your Inventory: Move 2, or Heal 1, or draw a card."))
rf("maximal_effect", "red", "Effetto Massimo (RotF)", "Maximal Effect (RotF)",
   [sp("maximal_effect", mode="basic", times=3)], [sp("maximal_effect", mode="powered", times=2)],
   "Quando giochi questa carta, getta via un'altra carta Azione dalla tua mano. Usa l'effetto base di quella carta tre volte.",
   "Quando giochi questa carta, getta via un'altra carta Azione dalla tua mano. Usa l'effetto più forte di quella carta due volte (gratuitamente).", 20,
   note="Uguale alla carta ufficiale.",
   te=("When you play this, throw away another Action card from your hand. Use the basic effect of that card three times.", "When you play this, throw away another Action card from your hand. Use the stronger effect of that card two times (for free)."))
rf("ebb_and_flow", "blue", "Flusso e Riflusso", "Ebb and Flow",
   [OPT(sp("rotf_flip_die")), sp("rotf_mana_shard", color="non_scarce"), sp("rotf_tuck", card="self")],
   [ATT(3, "ice"), sp("rotf_potion", action="attack_per_spent")],
   f"Puoi girare un dado mana di un colore base nella Riserva. Guadagni un {SH} di un colore non scarso. Puoi accantonare ('tuck') questa carta.",
   "Attacco di Ghiaccio 3. Questo Attacco aumenta di 1 per ciascuna delle tue Pozioni spese.", 21, impl=False, note=NOSH,
   te=("You may flip a mana die of a basic color in the Source. Gain a mana shard of a non-scarce color. You may tuck this card.", "Ice Attack 3. This Attack is increased by 1 for each of your spent Potions."))
rf("disrupting_ray", "white", "Raggio di Disturbo", "Disrupting Ray",
   [sp("reduce_enemy_attack", n=2), md("rotf_on_block_reward", shard="white")],
   [sp("rotf_arcane_vulnerability")],
   f"Riduci di 2 un attacco nemico. Se blocchi con successo quel nemico, guadagni un {SH} bianco.",
   "Il nemico bersaglio ottiene Vulnerabilità Arcana. Se lo blocchi con successo o ne impedisci l'attacco, perde anche tutte le resistenze.", 22,
   impl=False, combat_only=True, note=NOSH,
   te=("Reduce one enemy attack by 2. If you successfully block that enemy, gain a white mana shard.", "Target enemy gains Arcane Vulnerability. If you successfully block it or prevent its attack, it also loses all resistances."))
rf("pernicious_bolt", "green", "Dardo Pernicioso", "Pernicious Bolt",
   [ch([ATT(2), sp("rotf_poison_attack")], [MANA("green"), MANA("green")])],
   [ch([SIE(2), sp("rotf_poison_attack")], [CRY("green"), CRY("green")])],
   "Attacco 2 (veleno), oppure guadagni due segnalini mana verdi.",
   "Attacco d'Assedio 2 (veleno), oppure guadagni due cristalli verdi nel tuo Inventario.", 23, impl=False, note=NOSH,
   te=("Attack 2 (poison), or gain two green mana tokens.", "Siege Attack 2 (poison), or gain two green crystals to your Inventory."))
rf("thirst_for_power", "red", "Sete di Potere", "Thirst for Power",
   [sp("throw_action", any_color=True, effects=[sp("use_offer_card", offer="aa", mode="basic", times=2, free=True)])],
   [sp("rotf_tuck", card="hand", effects=[sp("use_offer_card", offer="aa", mode="powered", color="$tucked", free=True)])],
   "Getta via una carta Azione dalla tua mano per usare due volte l'effetto base di una carta dell'offerta delle Azioni Avanzate. La carta rimane nell'offerta.",
   "Accantona ('tuck') una carta dalla tua mano per usare l'effetto più forte di una carta dello stesso colore dell'offerta delle Azioni Avanzate senza pagarne il costo in mana. La carta rimane nell'offerta.", 24,
   impl=False, note=NOSH,
   te=("Throw away an Action card from your hand to use the basic effect of a card from the Advanced Actions offer twice. The card remains in the offer.", "Tuck a card from your hand to use the stronger effect of a card of the same color from the Advanced Actions offer, without paying its mana cost. The card remains in the offer."))
rf("witchs_brew", "blue", "Intruglio delle Streghe", "Witch's Brew",
   [ch([sp("rotf_potion", action="gain")], [sp("rotf_potion", action="refill", n=2)], [MANA("blue"), MANA("blue")])],
   [sp("use_as_action"), sp("rotf_tuck", card="hand", effects=[sp("gain_from_offer", offer="spells", color="$tucked", to="discard")])],
   "Guadagni una Pozione, ricarica fino a 2 Pozioni, oppure guadagni due segnalini mana blu.",
   "Giocala come tua azione per questo turno. Accantona ('tuck') una carta per guadagnare un Incantesimo dello stesso colore dall'offerta degli Incantesimi e mettilo nella tua pila degli scarti.", 25,
   impl=False, note=NOSH,
   te=("Gain a Potion, refill up to 2 Potions, or gain two blue mana tokens.", "Play as your action for this turn. Tuck a card to gain a Spell of the same color from the Spells Offer and put it in your discard pile."))
rf("gust_of_wind", "white", "Folata di Vento", "Gust of Wind",
   [MV(6), sp("gust_of_wind_restriction")],
   [sp("rotf_tuck", card="hand", effects=[sp("safe_move", spaces=4, cost_per_space=2, from_move_points=True)])],
   "Movimento 6. Puoi scartare una carta. Se non lo fai, questi punti Movimento non possono essere spesi per pagare i costi del terreno.",
   "Accantona ('tuck') una carta e paga fino a 8 punti Movimento per muovere di uno spazio ogni 2 punti Movimento pagati. Devi terminare il movimento in uno spazio sicuro. Muovere in questo modo non provoca i nemici infuriati.", 26,
   impl=False, note=NOSH,
   te=("Move 6. You may discard a card. If you don't, these move points cannot be spent to pay terrain costs.", "Tuck a card and pay up to 8 Move points to move one space for each 2 Move points paid. You must end your move in a safe space. Moving this way does not provoke rampaging enemies."))
rf("poison_handling", "green", "Manipolazione del Veleno", "Poison Handling",
   [sp("rotf_potion", action="refill"), ["draw", 1], sp("throw_wound_from_discard")],
   [sp("take_wound", to="discard"), sp("rotf_tuck", card="hand", effects=[RNG(5), sp("rotf_poison_attack")])],
   "Ricarica una Pozione, pesca una carta e getta via una Ferita dalla tua pila degli scarti.",
   "Guadagni una Ferita nella tua pila degli scarti e accantona ('tuck') una carta per ottenere Attacco a Distanza 5 (veleno).", 27,
   impl=False, note=NOSH,
   te=("Refill a Potion, draw a card, and throw away a Wound from your discard pile.", "Gain a Wound to your discard pile and tuck a card to gain Ranged Attack 5 (poison)."))
rf("dark_dealings", "red", "Affari Oscuri", "Dark Dealings",
   [ch([INF(4)], [ATT(2), sp("rotf_dagger")]), ["rep", -1]], [ATT(4), sp("rotf_dagger"), ["if", "day", [["rep", -1]]]],
   "Influenza 4 oppure Attacco 2 (pugnale). Reputazione -1.", "Attacco 4 (pugnale). Reputazione -1 se giocata durante il Giorno.", 28,
   impl=False, note=NOSH,
   te=("Influence 4 or Attack 2 (dagger). Reputation -1.", "Attack 4 (dagger). Reputation -1 if played during the Day."))
rf("cloud_of_steel", "blue", "Nube d'Acciaio", "Cloud of Steel",
   [ch([BLK(3)], [ATT(1), sp("rotf_dagger")], [sp("rotf_mana_shard", color="blue")])],
   [ATT(2, "ice"), sp("rotf_dagger"), md("delayed_attack", n=2, elem="ice", any_time=True)],
   f"Blocco 3, Attacco 1 (pugnale), oppure guadagni un {SH} blu.",
   "Attacco di Ghiaccio 2 (pugnale). (Durata) Guadagni Attacco di Ghiaccio 2 (pugnale) in qualsiasi momento di questo turno.", 29,
   impl=False, note=NOSH,
   te=("Block 3, Attack 1 (dagger), or gain a blue mana shard.", "Ice Attack 2 (dagger). Gain Ice Attack 2 (dagger) at any time this turn."))
rf("feinting_flare", "white", "Bagliore Ingannevole", "Feinting Flare",
   [ch([MANA("white"), MANA("white")], [ATT(1), sp("rotf_dagger")])],
   [ch([sp("reduce_enemy_attack", n=2, all_of_enemy=True), ATT(2), sp("rotf_dagger")], [CRY("white"), CRY("white")])],
   "Guadagni due segnalini mana bianchi oppure Attacco 1 (pugnale).",
   "Riduci di 2 tutti gli attacchi di un nemico e guadagni Attacco 2 (pugnale) contro un secondo nemico, oppure guadagni due cristalli bianchi nel tuo Inventario.", 30,
   impl=False, note=NOSH,
   te=("Gain two white mana tokens or Attack 1 (dagger).", "Reduce all attacks of one enemy by 2 and gain Attack 2 (dagger) against a second enemy, or gain two white crystals to your Inventory."))
rf("noxiousness", "green", "Nocività", "Noxiousness",
   [ch([MV(3)], [ATT(1), sp("rotf_dagger")], [sp("rotf_mana_shard", color="green")])],
   [ATT(3), sp("rotf_poison_attack"), sp("rotf_dagger")],
   f"Movimento 3, Attacco 1 (pugnale), oppure guadagni un {SH} verde.", "Attacco 3 (veleno, pugnale)", 31,
   impl=False, note=NOSH,
   te=("Move 3, Attack 1 (dagger), or gain a green mana shard.", "Attack 3 (poison, dagger)"))
rf("counter_attack", "red", "Contrattacco (RotF)", "Counter Attack (RotF)",
   [ATT(2), sp("attack_per_blocked", n=2)], [ATT(3), sp("attack_per_blocked", n=3)],
   "Attacco 2. Questo Attacco aumenta di 2 per ogni nemico che hai bloccato con successo in questo turno.",
   "Attacco 3. Questo Attacco aumenta di 3 per ogni nemico che hai bloccato con successo in questo turno.", 32,
   combat_only=True,
   te=("Attack 2. This Attack is increased by 2 for each enemy you have successfully blocked this turn.", "Attack 3. This Attack is increased by 3 for each enemy you have successfully blocked this turn."))
rf("perseverance", "blue", "Perseveranza", "Perseverance",
   [ch([BLK(3)], [MV(3)], [sp("unit_resist", elem="ice")])], [BLK(7)],
   "Blocco 3, Movimento 3, oppure l'Unità scelta guadagna Resistenza al Ghiaccio in questo combattimento.", "Blocco 7", 33,
   te=("Block 3, Move 3, or chosen Unit gains ice resistance this combat.", "Block 7"))
rf("heroic_tale", "white", "Racconto Eroico (RotF)", "Heroic Tale (RotF)",
   [INF(2), ["rep", 1], md("recruit_discount", n=3, units=1)],
   [INF(5), ["rep", 2], md("recruit_discount", n=2, units="all"), md("per_recruit", fame=1)],
   "Influenza 2. Reputazione +1. Se usata durante un'Interazione, ottieni uno sconto di 3 sul costo di reclutamento di un'Unità.",
   "Influenza 5. Reputazione +2. Se usata durante un'Interazione, ottieni uno sconto di 2 sul costo di reclutamento di ciascuna Unità. (Durata) Guadagni Fama +1 ogni volta che recluti un'Unità in questo turno.", 34,
   te=("Influence 2. Reputation +1. If used during Interaction, get a discount of 3 towards the cost of recruiting one Unit.", "Influence 5. Reputation +2. If used during Interaction, get a discount of 2 towards the cost of recruiting each Unit. Gain Fame +1 each time you recruit a Unit this turn."))
rf("reconnoiter", "green", "Ricognizione", "Reconnoiter",
   [ch([MV(3)], [HEAL(2)], [["draw", 1], sp("peek_enemy_piles", n=2)])], [MV(7)],
   "Movimento 3, Cura 2, oppure pesca una carta e guarda il gettone in cima a due qualsiasi pile di gettoni nemico non utilizzate.",
   "Movimento 7", 35,
   te=("Move 3, Heal 2, or draw a card and take a look at the top token of any two unused enemy token piles.", "Move 7"))
rf("fury", "red", "Furia (RotF)", "Fury",
   [ch([ATT(3)], [MANA("red"), MANA("red")], [sp("unit_resist", elem="fire")])], [ATT(7)],
   "Attacco 3, guadagni due segnalini mana rossi, oppure l'Unità scelta guadagna Resistenza al Fuoco in questo combattimento.",
   "Attacco 7", 36,
   te=("Attack 3, gain two red mana tokens, or chosen Unit gains fire resistance this combat.", "Attack 7"))
rf("repel_ritual", "blue", "Rituale Repulsivo", "Repel Ritual",
   [sp("repel_ritual", block=4, elem="phys")], [sp("repel_ritual", block=5, elem="ice")],
   "Blocco 4. Puoi gettare via un'altra carta non-Ferita. A seconda dei suoi colori: aumentalo di 2 per il blu, aggiungigli l'elemento Fuoco per il rosso, conta doppio contro un attacco con Rapidità per il verde, ottieni lo stesso Blocco contro un altro attacco per il bianco.",
   "Come l'effetto base, ma con Blocco di Ghiaccio 5.", 37, combat_only=True,
   te=("Block 4. You may throw away another non-Wound card. Depending on its colors: increase it by 2 for blue, add Fire element to it for red, count it twice against an attack with Swiftness for green, gain the same Block against another attack for white.", "Same as the basic effect, but with Ice Block 5."))
rf("righteous_path", "white", "Retto Cammino", "Righteous Path",
   [MV(2), sp("reduce_space_cost", n="rep_bonus", min=0)], [ch([MV(4)], [ATT(4)]), ["fame", 1], ["rep", 1]],
   "Movimento 2. Riduci il costo di Movimento di uno spazio del tuo bonus di Reputazione, fino a un minimo di 0, in questo turno.",
   "Movimento 4 oppure Attacco 4. Guadagni Fama +1 e Reputazione +1.", 38,
   te=("Move 2. Reduce the Move cost of one space by your Reputation bonus, to a minimum of 0, this turn.", "Move 4 or Attack 4. Gain Fame +1 and Reputation +1."))
rf("force_of_nature", "green", "Forza della Natura (RotF)", "Force of Nature (RotF)",
   [ch([BLK(3)], [sp("unit_resist", elem="phys")])], [ch([SIE(3)], [BLK(6)])],
   "Blocco 3 oppure l'Unità scelta guadagna Resistenza fisica in questo combattimento.", "Attacco d'Assedio 3 o Blocco 6", 39,
   combat_only=True,
   te=("Block 3 or chosen Unit gains Physical resistance this combat.", "Siege Attack 3 or Block 6"))
rf("ritual_attack", "red", "Attacco Rituale (RotF)", "Ritual Attack (RotF)",
   [sp("throw_action", discard_only=True, by_color={"red": [ATT(5)], "blue": [ATT(3, "ice")], "white": [RNG(3)], "green": [SIE(2)]})],
   [sp("throw_action", by_color={"red": [ATT(7, "fire")], "blue": [ATT(5, "cold")], "white": [RNG(5, "fire")], "green": [SIE(4, "fire")]})],
   "Scarta un'altra carta Azione. A seconda del suo colore ottieni: Attacco 5 se rossa, Attacco di Ghiaccio 3 se blu, Attacco a Distanza 3 se bianca, Attacco d'Assedio 2 se verde.",
   "Getta via un'altra carta Azione. A seconda del suo colore ottieni: Attacco di Fuoco 7 se rossa, Attacco di Fuoco Freddo 5 se blu, Attacco di Fuoco a Distanza 5 se bianca, Attacco di Fuoco d'Assedio 4 se verde.", 40,
   combat_only=True,
   te=("Discard another Action card. Depending on its color, you get: Attack 5 for red, Ice Attack 3 for blue, Ranged Attack 3 for white, Siege Attack 2 for green.", "Throw away another Action card. Depending on its color, you get: Fire Attack 7 for red, Cold Fire Attack 5 for blue, Ranged Fire Attack 5 for white, Siege Fire Attack 4 for green."))
rf("ice_shield", "blue", "Scudo di Ghiaccio (RotF)", "Ice Shield (RotF)",
   [BLK(3, "ice"), md("sideways_block_element", elem="ice")],
   [BLK(5, "ice"), md("sideways_block_element", elem="ice"), sp("block_armor_reduce", n=2, min=1)],
   "Blocco di Ghiaccio 3. (Durata) Aggiungi l'elemento Ghiaccio a ogni Blocco fornito dalle carte che giochi sul fianco in questo turno.",
   "Come l'effetto base, ma con Blocco di Ghiaccio 5. (Durata) Quando blocchi con successo il nemico bloccato da questo Blocco, riduci la sua armatura di 2.", 41,
   combat_only=True, note=ICE_RES.strip(),
   te=("Ice Block 3. Add Ice element to each Block provided by cards you play sideways this turn.", "Same as the basic effect, but with Ice Block 5. When you successfully block the enemy that is blocked by this Block, reduce their armor by 2."))
rf("learning", "white", "Imparare (RotF)", "Learning (RotF)",
   [INF(2), md("buy_aa_with_influence", cost=4, to="discard")], [INF(4), md("buy_aa_with_influence", cost=7, to="hand")],
   "Influenza 2. Una volta durante questo turno, puoi pagare Influenza 4 per guadagnare una carta Azione Avanzata dall'offerta delle Azioni Avanzate e metterla nella tua pila degli scarti.",
   "Influenza 4. Una volta durante questo turno, puoi pagare Influenza 7 per guadagnare una carta Azione Avanzata dall'offerta delle Azioni Avanzate e metterla nella tua mano.", 42,
   te=("Influence 2. Once during this turn, you may pay Influence 4 to gain an Advanced Action card from the Advanced Actions offer to your discard pile.", "Influence 4. Once during this turn, you may pay Influence 7 to gain an Advanced Action card from the Advanced Actions offer to your hand."))
rf("training", "green", "Allenarsi (RotF)", "Training (RotF)",
   [sp("throw_action", by_color={c: [sp("gain_from_offer", offer="aa", color="not:" + c, to="discard")] for c in BASIC4})],
   [sp("throw_action", by_color={c: [sp("gain_from_offer", offer="aa", color=c, to="hand")] for c in BASIC4})],
   "Getta via una carta Azione dalla tua mano, quindi prendi una carta di un colore diverso dall'offerta delle Azioni Avanzate e mettila nella tua pila degli scarti.",
   "Getta via una carta Azione dalla tua mano, quindi prendi una carta dello stesso colore dall'offerta delle Azioni Avanzate e mettila nella tua mano.", 43,
   te=("Throw away an Action card from your hand, then take a card of a different color from the Advanced Actions offer and put it into your discard pile.", "Throw away an Action card from your hand, then take a card of the same color from the Advanced Actions offer and put it into your hand."))
rf("shield_bash", "blue", "Colpo di Scudo (RotF)", "Shield Bash (RotF)",
   [sp("block_vs_swift", n=3, n_if_swift=6)], [sp("block_vs_swift", n=5, n_if_swift=10, armor_excess=True)],
   "Blocco 3. Conta doppio contro un attacco con Rapidità.",
   "Blocco 5. Conta doppio contro un attacco con Rapidità. (Durata) Se blocchi l'attacco usando più punti di blocco del necessario, riduci l'armatura del nemico dell'eccedenza.", 44,
   combat_only=True, note=ICE_RES.strip(),
   te=("Block 3. Counts twice against an attack with Swiftness.", "Block 5. Counts twice against an attack with Swiftness. If you block the attack using more points of block than required, reduce the enemy's armor by the excess."))

# ---------------------------------------------------------------- starting decks (from the mod's Lua gameCards "Starting")
STANDARD_DECK = {"stamina": 2, "determination": 1, "crystallize": 1, "march": 2, "tranquility": 1, "concentration": 1,
                 "swiftness": 2, "mana_draw": 1, "promise": 1, "improvisation": 1, "threaten": 1, "rage": 2}
HERO_SET = {"arythea": "base", "goldyx": "base", "norowas": "base", "tovak": "base", "wolfhawk": "ll", "krang": "krang",
            "braevalar": "tezla", "coral": "fan", "ymirgh": "fan", "mevok": "fan", "duscenia": "fan", "jormund": "fan",
            "malek": "fan", "zirtae": "fan"}
EXTRA_REPL = {"jormund": {"rotf_concentration": "concentration"}}   # carte sostitutive senza campo hero

def deck_for(hero):
    d = []
    repl = {c["id"]: c["replaces"] for c in CARDS if c["type"] == "basic" and c["hero"] == hero and c.get("replaces")}
    repl.update(EXTRA_REPL.get(hero, {}))
    cnt = dict(STANDARD_DECK)
    for cid, r in repl.items():
        cnt[r] -= 1
        cnt[cid] = cnt.get(cid, 0) + 1
    for k, v in cnt.items():
        d += [k] * v
    return d

# mazzi del modulo per la verifica: letti dal Lua (gameCards, voci "Starting" sotto "--<Eroe> Starting Cards")
LUA = '/home/claude/work/global.lua'
LUA_NAME = {"noble_promise": "noble_manners", "quick-witted": "quick_witted", "infamous__reprisals": "infamous_reprisals"}

def mod_decks():
    if not os.path.exists(LUA):
        return {}
    decks, cur = {}, None
    for line in open(LUA, encoding='utf-8', errors='replace'):
        m = re.match(r'\s*--\s*(\w+) Starting Cards', line)
        if m:
            cur = m.group(1).lower().replace('braevelar', 'braevalar')
            decks[cur] = []
            continue
        if cur and 'cardType="Starting"' in line:
            n = re.search(r'name=\{"([^"]*)"', line).group(1).lower().replace(' ', '_')
            n = LUA_NAME.get(n, n)
            if cur == 'duscenia' and n == 'regeneration':
                n = 'duscenia_regeneration'
            decks[cur].append(n)
        elif cur and line.strip().startswith('--'):
            cur = None
        elif cur and 'cardType=' in line and 'Starting' not in line:
            cur = None
    return decks

# ---------------------------------------------------------------- specials / mods descriptions
SPECIALS = {
 "_conventions": {"desc": "Conventions used by cards_basic.json/cards_aa.json (not a special). (1) In a ['choice', …] an empty option [] means declining an optional effect ('you may…'). (2) ['terrain', {…}] dict values: integer n = the terrain costs n this turn (an impassable terrain such as lake/mountain becomes passable); '-k' = cost reduced by k; '<=k' = cost becomes min(cost,k); key 'all' = every passable terrain (plains, hills, forest, wasteland, desert, swamp; not lake/mountain); key 'min' = floor for '-k' reductions (default 0); key 'safe': [terrains] = those terrains also count as safe spaces where you may end the turn (otherwise a terrain made passable, e.g. lake via Frost Bridge, is NOT safe). Terrain ids: plains, hills, forest, wasteland, desert, swamp, lake, mountain. (3) ['boost_next', n] (Concentration, Will Focus): the player must immediately play another Action card (basic/advanced, not Spell/Artifact/Wound) from hand; it resolves its POWERED effect without paying mana, and every Move/Influence/Block/Attack value it provides gets +n (applied to the chosen option if it is a choice; for multi-target effects such as Maximal Effect each produced value gets +n). (4) Card params '$paid' = color of the mana/crystal just paid; '$thrown' etc. are not used — throw_action uses explicit by_color tables. (5) Dual-color cards have 'colors': [c1, c2]; they can be powered with mana of either color and count as both colors for color matching (offer selection, Decompose, Training…); when a dual card is thrown away by throw_action the player picks which of its colors applies. (6) Notes in Italian on each card (field 'note') list timing restrictions.", "used_by": []},
 "take_wound": {"desc": "Take Wound card(s) from the Wound pile. Params: n (default 1), to: 'hand' (default) | 'discard' | 'hand_or_discard' (player chooses). Wounds taken to hand during combat count for Knock Out (Colpo di Grazia) and trigger draw_on_wound/prevent_next_wound; they are not damage (armor/poison/paralyze do not apply). If the Wound pile is empty the effect still happens (use a virtual wound)."},
 "block_armor_reduce": {"desc": "Combat, Block phase. When the block points of this card are used to successfully block an enemy, that enemy's Armor is reduced by n for the rest of this combat (never below min, default 1). Blue-card non-attack effect: enemies with Ice Resistance are not affected (and for red cards Fire Resistance). Params: n, min."},
 "influence_per_wound": {"desc": "Gain n extra Influence for each Wound card in your hand plus each Wound on Units you control (i.e. each wounded Unit counts 1). Counted when the card is played. Params: n."},
 "throw_action": {"desc": "Throw away (remove from the game) one Action card (Basic or Advanced Action, not Spell/Artifact/Wound) from your hand other than this card, then apply by_color[color of the thrown card] (for dual-color cards the player chooses one of its colors). Params: by_color {red|blue|green|white: [effects]}; discard_only:true = the card is only discarded (to discard pile) instead of thrown away; any_color:true + effects:[…] = apply 'effects' regardless of color. The card cannot be played in that mode if no eligible Action card is in hand."},
 "gain_from_offer": {"desc": "Take a card from an offer. Params: offer 'aa'|'spells'; color: a basic color, '$paid', 'not:<color>' (any card whose color differs), 'lowest' (the card in the lowest/oldest offer position); to: 'hand'|'discard'|'deck_top' (default deck_top per rules). Dual-color AAs match either color. Player chooses among matching cards; if none, nothing happens. The offer is refilled immediately (remaining cards slide down, new card on top) as in the rules for gaining from the AA/Spell offer."},
 "maximal_effect": {"desc": "Throw away another Action card (Basic or Advanced Action, not Spell/Artifact/Wound) from your hand and resolve its effect 'times' times: mode 'basic' = its basic effect; mode 'powered' = its stronger effect without paying mana. Each repetition is resolved separately (separate choices), but it counts as one compound effect (e.g. with Determination the Blocks may be used against different attacks). The thrown card keeps its color for resistance purposes. Params: mode, times."},
 "crystal_copy": {"desc": "Gain one crystal of the same color as a crystal you already own (choose among colors with >=1 crystal). If that color is already at 3 you gain a mana token instead (normal overflow rule). Not playable if you have no crystals."},
 "crystals_return": {"kind": "mod", "desc": "Crystal Mastery powered: every crystal spent from your Inventory during this turn (including those spent earlier in the turn, before this card was played) returns to your Inventory at the end of the turn (respecting the 3-per-color limit)."},
 "crystal_from_source_die": {"desc": "Choose a die in the Source showing a basic color (not taken by anyone, not depleted); gain a crystal of that color; then (reroll:true) immediately reroll that die and return it to the Source (black at day/gold at night → depleted as usual). Does not count as using a die."},
 "reroll_source": {"desc": "Reroll all dice currently in the Source (not those taken by players). Apply the normal day/night depletion of black/gold."},
 "source_black_gold_any": {"kind": "mod", "desc": "This turn you may use dice from the Source showing black or gold as mana of any basic color, regardless of Day/Night."},
 "first_attack_or_block_bonus": {"kind": "mod", "desc": "This turn, the first card you play that provides any type of Attack gets +attack, OR the first card that provides any type of Block gets +block — only whichever of the two you play first (the other bonus is lost). Sideways cards count as Attack/Block cards. Params: attack, block (missing = 0)."},
 "magic_talent": {"desc": "Official (no params): discard one card from hand (not a Wound); this turn you may cast one Spell of the same color that is in the Spells offer as if it were in your hand (pay its mana as usual: basic = 1 mana of its color, powered = + black at night); the Spell stays in the offer. variant 'basic_pay' (RotF): discard a card of any color, then use the BASIC effect of a Spell of that color in the offer by paying its mana cost; the Spell stays in the offer."},
 "buy_aa_with_influence": {"kind": "mod", "desc": "Once this turn (any time in the turn, also outside a site) you may spend 'cost' Influence points to take any Advanced Action from the AA offer and put it in 'to' ('discard'|'hand'). Offer refilled immediately."},
 "use_offer_card": {"desc": "Resolve the effect of a card in an offer without taking it (it remains in the offer). Params: offer 'aa'|'spells'; mode 'basic'|'powered'; free (true = no mana cost; false = pay its normal cost); color (optional restriction, e.g. '$paid'); times (default 1). Counts as a compound effect; the used card keeps its color for resistance purposes."},
 "attack_per_blocked": {"desc": "Add extra melee physical Attack n for each enemy you have successfully blocked in this combat (counted when the attack is used in the Attack phase; if played earlier, recount at the Attack phase). Params: n."},
 "block_vs_swift": {"desc": "Gain physical Block n. When this block is used against an attack with Swiftness (Rapidità) its value counts as n_if_swift instead (i.e. it counts double; the doubled requirement of Swiftness still applies to the total). If armor_excess:true and the block succeeds, the blocked enemy's Armor is reduced by the number of block points in excess of what was required, to a minimum of 1, for the rest of combat (blue card: Ice-resistant enemies ignore the Armor reduction). Params: n, n_if_swift, armor_excess."},
 "use_as_action": {"desc": "Playing this (or this option) uses your action for the turn: allowed only if you have not yet taken an action (combat, interaction, site entry…) this turn, and afterwards no other action may be taken. Movement before it is allowed; no further movement after it."},
 "safe_move": {"desc": "Move your figure up to 'spaces' spaces, through/into revealed spaces, ending in a safe revealed space, ignoring terrain costs and without provoking rampaging enemies (no move points spent unless from_move_points:true with cost_per_space). Optional (you may stay). Params: spaces, cost_per_space, from_move_points."},
 "hand_limit_next": {"kind": "mod", "desc": "The next time you draw cards (end of this turn) your Hand limit is increased. Params: any:n = +n unconditionally; hills:n / mountain:n = +n if you end the turn on that terrain (use the matching value only)."},
 "crystal_from_offer": {"desc": "Gain n crystals whose colors match n DIFFERENT Spell cards currently in the Spells offer (n=2: two crystals matching two different cards; same color allowed if two different cards share it). Params: offer 'spells', n."},
 "attack_with_kill_reward": {"desc": "Gain an Attack of n (elem default 'phys', kind default 'melee'; e.g. kind 'ranged'). The engine tracks the enemies defeated by an attack in which this card's points were used; for each enemy defeated by it: Reputation +rep and Fame +fame; armor_minus_other:k = for each defeated enemy, choose another (undefeated) enemy in this combat whose Armor is reduced by k (min 1) for the rest of combat; fame_once:k = Fame +k once if at least one enemy was defeated. Params: n, elem, kind, rep, fame, armor_minus_other, fame_once."},
 "influence_to_heal": {"kind": "mod", "desc": "This turn you may convert Influence into Heal: each 'per' Influence spent gives Heal 1 (healing rules apply; not during combat). Params: per."},
 "ready_units_for_influence": {"kind": "mod", "desc": "This turn you may ready (refresh) exhausted Units you control by paying per_level Influence × the Unit's level, for Units of level <= max_level. Params: per_level, max_level."},
 "reduce_enemy_attack": {"desc": "Combat, Block phase: reduce the Attack value of one enemy attack by n (minimum 0) for this combat. attacks:2 = instead reduce two different attacks (of one or two enemies) by n each. all_of_enemy:true = all attacks of one enemy. Params: n, attacks, all_of_enemy. White card: no resistance blocks it."},
 "attack_if_no_wounds": {"kind": "mod", "desc": "In the Attack phase of this combat you gain melee physical Attack n if no Wound cards were added to your hand during the previous phases of this combat. Params: n."},
 "stout_resolve": {"desc": "Choose Move n, Influence n, Attack n or Block n (physical melee). Then you may discard cards from hand to increase the chosen value by 'per' each: wounds_only:true = you may discard up to max_cards Wound(s) (basic: 1 Wound, +1); otherwise up to max_cards cards of any kind, of which at most max_wounds may be Wounds (powered: any number of cards incl. one Wound, +2 each). Discarded Wounds go to the discard pile. Params: n, per, max_cards, max_wounds, wounds_only."},
 "unit_resist": {"desc": "Choose one of your Units; it gains Resistance to elem ('phys'|'fire'|'ice') for the rest of this combat. Params: elem."},
 "crystal_new_color": {"desc": "Gain one crystal of a basic color of which you currently have 0 crystals (player chooses among such colors). Not playable if you own all four colors."},
 "repeat_per_crystal_set": {"desc": "For each complete set of four crystals of different basic colors in your Inventory (= min over the 4 colors of the crystal count), resolve 'effects' once (choices made separately). Params: effects."},
 "draw_on_wound": {"kind": "mod", "desc": "Rush of Adrenaline. For each of the first n Wounds taken into your hand this turn, draw a card (immediately). Wounds already taken to hand earlier this turn count (draw for them when the card is played). throw_first:true (powered): the FIRST Wound taken to hand this turn is thrown away (returned to the Wound pile) and you draw a card; then for each of the next n Wounds you draw a card. Params: n, throw_first."},
 "enemy_attack_strip": {"desc": "Combat (before blocks): what:'abilities' = choose an enemy attack; it loses all attack abilities (Swift, Brutal, Poison, Paralyze, and summon if applicable) but keeps its element/color, for this combat. what:'one' = remove ONE attack element (attack becomes physical) or ONE attack ability of one enemy token. Resistances block it as a non-attack effect of the card's color."},
 "enemy_no_attack": {"desc": "Combat (Block phase): one chosen enemy does not attack this combat (its attacks are ignored, no damage). unfortified:true = only an enemy that is not fortified. Arcane Immunity (expansion) and resistance to the card's color prevent it."},
 "mana_draw": {"desc": "Take 'dice' dice from the Source (in addition to the normal die), set each to any color except gold (black allowed), gain 'tokens' mana tokens of that color per die; these dice are not rerolled when returned at end of turn (they stay on the chosen face). They are not usable as mana themselves. Params: dice, tokens."},
 "extra_black_die_any": {"kind": "mod", "desc": "Mana Pull basic: the additional die granted by this card, if it shows black, may be used as mana of any color (also by Day)."},
 "per_recruit": {"kind": "mod", "desc": "For each Unit you recruit this turn (after playing the card) gain Reputation +rep and Fame +fame. Params: rep, fame."},
 "units_bonus": {"kind": "mod", "desc": "Into the Heat: for this combat, every Attack (any type/element) and Block value provided by your Units' abilities gets +attack / +block; you cannot assign damage to Units this turn (no_unit_damage). Playable only at the start of combat (before the Ranged/Siege phase). Params: attack, block, no_unit_damage."},
 "card_to_deck_end_turn": {"kind": "mod", "desc": "At end of turn, instead of putting this card in the discard pile you may put it on the 'bottom' (only if your Deed deck is not empty) or 'top' of your Deed deck. Params: pos."},
 "influence_as_block": {"kind": "mod", "desc": "This turn you may use Influence points as Block points of element elem ('phys' or the chosen 'ice'/'fire'). Params: elem."},
 "move_to_attack": {"kind": "mod", "desc": "During combat this turn you may spend Move points: 'melee' Move points for each melee physical Attack 1 and/or 'ranged' Move points for each Ranged physical Attack 1. Params: melee, ranged (missing = not allowed)."},
 "interaction_bonus": {"kind": "mod", "desc": "If Influence from this card is used during an interaction (recruiting, healing, buying at a site) this turn, gain Fame +fame and Reputation +rep (once). Params: fame, rep."},
 "block_per_enemy_ability": {"desc": "Cold Toughness powered: when this Ice Block is used against an enemy, it gets +n for each ability icon and each attack-color (element) icon shown on that enemy token (count non-physical attack element once, plus each special ability, incl. defensive ones), unless the enemy has Arcane Immunity. (Vs another player: +n per mana spent by the opponent during that attack.) Params: n, elem."},
 "move_card_bonus": {"kind": "mod", "desc": "Each later card this turn that provides Move (including cards played sideways for Move) gives +n Move; cards:1 = only the next such card, cards:'all' = every other such card. Params: n, cards."},
 "crystal_on_move": {"kind": "mod", "desc": "Savage Harvesting: this turn, when you move into a space, you may discard a non-Wound card from hand to gain a crystal of that card's color (Artifact: any basic color; dual-color: choose). times:1 = only once this turn; 'each' = each time you move a space. Params: times."},
 "recruit_discount": {"kind": "mod", "desc": "This turn, the Influence cost of recruiting Units is reduced by n: units:1 = for one Unit only, units:'all' = for each Unit recruited. rep: Reputation change applied if you recruit a discounted Unit (Ruthless Coercion: -1). Params: n, units, rep."},
 "reduce_space_cost": {"desc": "Choose one space (when you move into it this turn); its Move cost is reduced by n, to a minimum of min. terrain: restrict to a terrain type. n:'rep_bonus' = reduce by your current Reputation influence bonus (0 or negative = no reduction). Params: n, min, terrain."},
 "block_by_terrain": {"desc": "One with the Land powered: Block equal to the unmodified Move cost of the space you are in for the current Day/Night (mountains count 5, lakes 2; cities count their terrain cost); it is Fire Block during the Day and Ice Block at Night."},
 "return_card_end_turn": {"kind": "mod", "desc": "Crystal Joy: at end of turn you may discard another card from hand (wound_ok:false = non-Wound only; true = any, including a Wound) to return this card to your hand instead of the discard pile. Params: wound_ok."},
 "delayed_attack": {"kind": "mod", "desc": "Gain a melee Attack n (elem default 'phys') that becomes available in the Attack phase of the current combat (any_time:true = usable at any time this turn, also later in the turn). Params: n, elem, any_time."},
 "attack_vs_resistant": {"desc": "Melee physical Attack n; if any enemy targeted by this attack has any resistance, the attack is n_if_resist instead. Params: n, n_if_resist."},
 "attack_per_combat_wound": {"desc": "Battle Rage: increase this card's Attack by n for each Wound card you received (to hand) during the current combat, up to max. Params: n, max."},
 "terrain_count_reward": {"kind": "mod", "desc": "If during this turn you move through (enter) at least 'count' spaces of 'terrain', apply 'effects' once. Params: terrain, count, effects."},
 "wounds_sideways": {"desc": "Duscenia's Regeneration. You may play Wound cards from hand sideways (normally forbidden) as Move/Influence/Attack/Block. n:1, mult:2, then:'discard' = one Wound played sideways gives 2 instead of 1, then the Wound goes to your discard pile. n:2, bonus:1, throw:1 = two Wounds played sideways (1 each), the total is increased by 1, then one of those Wounds is thrown away (to the Wound pile) and the other discarded. Params: n, mult, bonus, then, throw."},
 "heal_any_pile": {"desc": "Heal n, where up to discard_max of the Heal points may be used to throw away Wounds from your discard pile (instead of from hand). Not during combat. Params: n, discard_max."},
 "bounty": {"desc": "Malek's Bounty Hunter: place a Bounty (shield) on any visible enemy (on the map or in combat). That enemy has Armor -armor. If you defeat it: Fame +fame and Reputation +rep. If it is a rampaging enemy, you may start a combat with it from up to 'range' spaces away, in which only the Ranged/Siege phase is fought (melee attacks impossible; the enemy does not attack you). Params: armor, fame, rep, range."},
 "convert_attack_card_to_ranged": {"desc": "Deadly Precision: play this together with another Attack card from hand: that card's attack (value and elements, basic or powered — the second card's powered effect still requires mana) becomes a Ranged attack preserving elements."},
 "play_with_bonus": {"desc": "RotF Concentration/Will Focus/Diligence: play another Action card from hand with a +bonus to its Move/Influence/Block/Attack values; you may use either its basic effect or its stronger effect without paying mana. Params: bonus."},
 "recolor_crystal": {"desc": "Change the color of one crystal in your Inventory to any basic color (respecting the 3-per-color limit)."},
 "pay_crystal": {"desc": "Spend one crystal from your Inventory (not a token/die). Then apply 'effects' with $paid = that crystal's color, or by_color[color]. Params: effects | by_color."},
 "discard_card": {"desc": "Discard another card from hand (wound_ok:true = it may be a Wound), then apply effects. Params: wound_ok, effects."},
 "no_provoke": {"kind": "mod", "desc": "This turn your movement does not provoke rampaging enemies."},
 "deed_discount": {"kind": "mod", "desc": "The next 'cards' Deed cards (AA/Spell/Artifact) you buy during interaction get a cost discount of n each. Params: n, cards."},
 "boost_this": {"desc": "Increase the value produced by this card's chosen option by n. Params: n."},
 "discard_wounds_bonus": {"desc": "You may discard up to 'max' Wound cards from hand (to discard pile); this card's Attack/Block value increases by 'per' for each. Params: max, per."},
 "heal_unit_ready": {"desc": "Heal one wounded Unit of level <= max_level (free); if you do, ready it and apply 'then'. Params: max_level, then."},
 "throw_wound_from_discard": {"desc": "Throw away one Wound from your discard pile (to the Wound pile); if you do, apply 'then'. Params: then."},
 "prevent_next_wound": {"kind": "mod", "desc": "The next time this turn you would gain a Wound to your hand, prevent it and any additional effects from it (e.g. poison), and draw 'draw' cards. Params: draw."},
 "sideways_block_element": {"kind": "mod", "desc": "This turn, Block provided by cards played sideways has element elem. Params: elem."},
 "peek_enemy_piles": {"desc": "Look at the top token of n unused enemy token piles (draw piles) and put them back. Params: n."},
 "repel_ritual": {"desc": "RotF Repel Ritual: Block 'block' of element 'elem'. You may throw away another non-Wound card from hand; for each of its colors: blue = this Block +2; red = add Fire to its element (ice+fire = cold fire); green = counts twice against an attack with Swiftness; white = gain the same Block (value/element) against another attack. Params: block, elem."},
 "gust_of_wind_restriction": {"desc": "RotF Gust of Wind basic: you may discard a card; if you don't, the Move 6 from this card cannot be spent to pay terrain costs (only for other uses such as exploring)."},
 "ignore_hero_damage": {"desc": "Ignore the next phys points of damage assigned to your hero from a single physical attack (or 'other' points from a non-physical attack) this combat. Params: phys, other."},
 "mevok_reprisals": {"desc": "Fan hero Mevok 'Infamous Reprisals' – reputation tricks ('X Rep is -5', using another Knight's reputation by paying black mana, solo +3, adding the +/- icon to a unit in the offer). Text is ambiguous; NOT implementable without the fan rules (card impl:false)."},
 "mevok_horde": {"desc": "Fan hero Mevok 'Undead Horde' – reanimating defeated enemies into Hordes (fan subsystem). NOT implementable without the fan rules (card impl:false)."},
 "rotf_mana_shard": {"desc": "Rise of the Forgemaster fan mechanic: gain a 'mana shard' of the given color. Requires the RotF shard subsystem (not in this game) → cards using it are impl:false."},
 "rotf_tuck": {"desc": "Rise of the Forgemaster fan mechanic 'tuck' (set a card aside under the RotF rules). Not in this game → impl:false."},
 "rotf_prepare": {"desc": "Rise of the Forgemaster fan mechanic 'prepare this card'. Not in this game → impl:false."},
 "rotf_potion": {"desc": "Rise of the Forgemaster fan mechanic: Potions (gain/refill/spend). Not in this game → impl:false."},
 "rotf_flip_die": {"desc": "Rise of the Forgemaster fan mechanic: flip a Source die of a basic color (RotF 'flip'). Not in this game → impl:false."},
 "rotf_cumbersome": {"desc": "Rise of the Forgemaster fan mechanic: target enemy gains 'Cumbersome'. Not in this game → impl:false."},
 "rotf_poison_attack": {"desc": "Rise of the Forgemaster: the attack has the poison (drop) icon — poison effect against enemies under RotF rules. Not in this game → impl:false."},
 "rotf_dagger": {"desc": "Rise of the Forgemaster: the attack has the dagger icon (RotF attack keyword). Not in this game → impl:false."},
 "rotf_arcane_vulnerability": {"desc": "Rise of the Forgemaster: target enemy gains Arcane Vulnerability; if you successfully block it or prevent its attack it also loses all resistances. Requires RotF rules → impl:false."},
 "rotf_on_block_reward": {"kind": "mod", "desc": "RotF: if you successfully block that enemy, gain a mana shard. → impl:false."},
 "rotf_lake_reward": {"kind": "mod", "desc": "RotF Treasure Hunt: reward (mana shard/crystal) if you end your move phase within 'near' spaces of a lake. → impl:false."},
 "rotf_shard_on_move": {"kind": "mod", "desc": "RotF Savage Harvesting: like crystal_on_move but gives a mana shard. → impl:false."},
}

# ---------------------------------------------------------------- build
def walk(effs, found):
    if isinstance(effs, list):
        if len(effs) >= 2 and effs[0] in ("special", "mod") and isinstance(effs[1], str):
            found.add(effs[1])
            if len(effs) > 2:
                walk(effs[2], found)
            return
        for x in effs:
            walk(x, found)
    elif isinstance(effs, dict):
        for v in effs.values():
            walk(v, found)

def find_src(idx_entries, src):
    key, i = src
    for e in idx_entries:
        f = e['face_en'] or ''
        if os.path.basename(f).endswith(key + '.jpg') and e['idx'] == i:
            return e
    raise KeyError(src)

def sheet_file(key):
    g = glob.glob(os.path.join(IMGDIR, '*' + key + '.jpg'))
    if not g:
        raise FileNotFoundError(key)
    return g[0]

def save_webp(im, path):
    from PIL import Image
    im = im.convert('RGB').resize((CARD_W, CARD_H), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, 'WEBP', quality=85, method=6)

def build_images(force=False):
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    from card_index import crop
    idx = json.load(open(INDEX))
    # ordina per foglio per non ricaricare i fogli enormi più volte
    todo = []
    for c in CARDS:
        out = os.path.join(ROOT, c["img"])
        if force or not os.path.exists(out):
            todo.append(c)
    def sk(c):
        return str(c["_src"][0])
    for c in sorted(todo, key=sk):
        out = os.path.join(ROOT, c["img"])
        if c["_src"][0] == "WHOLE":
            im = Image.open(sheet_file(c["_src"][1]))
        else:
            e = find_src(idx, c["_src"])
            im = crop(e, 'it')
        save_webp(im, out)
    for name in ("back_action", "back_aa"):
        out = os.path.join(ROOT, f"assets/cards/{name}.webp")
        if force or not os.path.exists(out):
            save_webp(Image.open(sheet_file(BACK_IMG)), out)
    return len(todo)

def output_cards(cs):
    res = []
    for c in cs:
        c = {k: v for k, v in c.items() if not k.startswith("_")}
        res.append(c)
    return res

def build_data():
    basic = [c for c in CARDS if c["type"] in ("basic", "wound")]
    aas = [c for c in CARDS if c["type"] == "aa"]
    decks = {h: deck_for(h) for h in HERO_SET}
    json.dump({"cards": output_cards(basic),
               "standard_deck": STANDARD_DECK,
               "hero_decks": decks,
               "hero_sets": HERO_SET},
              open(os.path.join(ROOT, "data/cards_basic.json"), "w"), ensure_ascii=False, indent=1)
    json.dump({"cards": output_cards(aas)}, open(os.path.join(ROOT, "data/cards_aa.json"), "w"), ensure_ascii=False, indent=1)
    used = {}
    for c in CARDS:
        f = set()
        walk([c["basic"], c["powered"]], f)
        for n in f:
            used.setdefault(n, []).append(c["id"])
    sp_out = {}
    for n, d in SPECIALS.items():
        if n.startswith("_"):
            sp_out[n] = d
            continue
        if n not in used:
            continue
        e = {"desc": d["desc"], "used_by": sorted(used[n])}
        if d.get("kind"):
            e["kind"] = d["kind"]
        sp_out[n] = e
    json.dump(sp_out, open(os.path.join(ROOT, "data/specials_actions.json"), "w"), ensure_ascii=False, indent=1)
    return used

def validate(used):
    errs = []
    ids = [c["id"] for c in CARDS]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        errs.append(f"duplicate ids {dup}")
    for c in CARDS:
        if not os.path.exists(os.path.join(ROOT, c["img"])):
            errs.append(f"missing image {c['img']}")
        if c["type"] == "basic" and c["hero"] and c.get("replaces") and c["replaces"] not in STANDARD_DECK:
            errs.append(f"{c['id']} replaces unknown {c['replaces']}")
    for n in used:
        if n not in SPECIALS:
            errs.append(f"special/mod '{n}' not described")
    for f in ("cards_basic.json", "cards_aa.json", "specials_actions.json"):
        json.load(open(os.path.join(ROOT, "data", f)))
    allids = set(ids)
    for h, d in ((h, deck_for(h)) for h in HERO_SET):
        if len(d) != 16:
            errs.append(f"deck {h} has {len(d)} cards")
        for x in d:
            if x not in allids:
                errs.append(f"deck {h}: unknown card {x}")
    md_ = mod_decks()
    for h in HERO_SET:
        if h not in md_:
            errs.append(f"deck {h} not found in mod Lua")
            continue
        a, b = sorted(deck_for(h)), sorted(md_[h])
        if a != b and h != "jormund":
            errs.append(f"deck {h} differs from mod: {sorted(set(a)^set(b))}")
    return errs

if __name__ == "__main__":
    args = sys.argv[1:]
    if "--check" not in args:
        n = build_images(force="--images" in args)
        print("images written:", n)
    used = build_data()
    errs = validate(used)
    import collections
    cnt = collections.Counter((c["type"], c["set"]) for c in CARDS)
    print("cards:", dict(cnt), "impl false:", [c["id"] for c in CARDS if not c["impl"]])
    print("specials/mods used:", len(used))
    if errs:
        print("ERRORS:\n  " + "\n  ".join(errs))
        sys.exit(1)
    print("OK")
