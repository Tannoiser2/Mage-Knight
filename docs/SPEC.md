# Mage Knight digitale — specifica tecnica (per chi sviluppa)

Godot **4.7**, GDScript, renderer `gl_compatibility` (deve girare sul web, export `Web` senza thread).
Testi dell'interfaccia **in italiano**. Codice e commenti possono essere in italiano o inglese.
Riferimento di stile/architettura: i progetti già fatti dell'utente in `/home/claude/ref-BEAST` (motore a
strati, tavolo 3D, Meshy, online con Firebase) e `/home/claude/ref-kingsburg` (online in lockstep).

Repo: `/home/claude/mage-knight` (GitHub `Tannoiser2/Mage-Knight`, Pages attivo via `.github/workflows/pages.yml`).

## 0. Ambito della prima versione
- Gioco base di Mage Knight (Ultimate Edition, contenuto del gioco base): tessere Campagna 1–11,
  tessere Centrali 1–4 + Città 5–8, tessere iniziali A (cuneo) e B (aperta), nemici verdi/grigi/marroni/
  viola/rossi/bianchi + segnalini Rovine gialli, eroi **Arythea, Goldyx, Norowas, Tovak** (gli altri eroi
  del modulo — Wolfhawk, Krang, Braevalar — se il tempo lo permette).
- Carte: tutte quelle presenti nei mazzi del modulo vengono **trascritte** (dati + immagine); ogni carta ha
  `impl: true/false`. Il setup della partita usa solo le carte `impl:true` del set scelto (default `base`).
- Scenari: *Prima ricognizione* (introduttivo), *Conquista in solitario* (con il giocatore fantoccio),
  *Conquista cooperativa* (2–4 eroi umani/IA contro le città), *Conquista completa* (competitiva, 2–4 eroi,
  con il combattimento tra giocatori, opzionale) e l'assalto cooperativo alle città in *Cooperazione totale*.
- IA per gli eroi non umani (alleati in cooperativa, avversari in competitiva).
- Online su Firebase in **lockstep** (stesso seme, stesse azioni) come Kingsburg.
- Mappa 3D ruotabile/zoomabile; figure 3D degli eroi e delle città dal modulo TTS; dove manca un modello
  3D, sagoma/segnalino 3D sostituibile da `assets/miniatures/<id>.glb` (generabile con Meshy).

## 1. Struttura dei file
```
project.godot, export_presets.cfg, .github/workflows/pages.yml
data/*.json                 dati statici (caricati a runtime, export include_filter "*.json")
  tiles.json  enemies.json  ruins.json  heroes.json  cards.json  units.json  skills.json
  tactics.json  cities.json  scenarios.json  rules.json  assets.json  specials.json
scripts/data/db.gd          caricamento dei JSON (class_name MKDB, statico, cache)
scripts/core/rng.gd         generatore pseudocasuale deterministico (stato nel dizionario di stato)
scripts/core/hexmap.gd      coordinate esagonali, vicini, tessere, forme della mappa
scripts/core/engine.gd      motore (class_name MKEngine) — stato + apply(azione); nessuna UI
scripts/core/effects.gd     interprete del DSL degli effetti delle carte/unità/abilità
scripts/core/combat.gd      combattimento
scripts/core/specials.gd    effetti speciali con nome (vedi specials.json)
scripts/core/ai.gd          IA
scripts/net/*.gd            Firebase REST + sessione online lockstep
scripts/ui/*.gd             menu, tavolo 3D, HUD, finestre
assets/…                    immagini/modelli (vedi §7)
tests/sim.gd                partite IA contro IA senza grafica: godot --headless -s res://tests/sim.gd
```
Godot di prova nel container: `/home/claude/tools/Godot_v4.7-stable_linux.x86_64` (modelli di export web
già installati). Import: `godot --headless --path . --import`.

## 2. Coordinate e mappa
- Esagoni **a punta in alto**, coordinate assiali `(q, r)`; chiave stringa `"q,r"`.
  Pixel/mondo: `x = √3·(q + r/2)`, `z = 1.5·r` (z positivo = sud, cioè verso chi guarda).
- Vicini (ordine fisso): W(-1,0) SW(-1,+1) SE(0,+1) E(+1,0) NE(+1,-1) NW(0,-1).
- Dati delle tessere (dal Lua del modulo, `terrainTiles`): le chiavi direzionali corrispondono a
  `"center"`=(0,0), `"0"`=W, `"60"`=SW, `"120"`=SE, `"180"`=E, `"240"`=NE, `"300"`=NW.
  Verificato su immagine (tessera 1: villaggio a E, lago a NE, orchi a NW). Le tessere non si ruotano mai.
- Una tessera = 7 esagoni (centro + 6 vicini). Centri delle tessere adiacenti (vettori "macro"):
  `N=(1,-3) NE=(3,-2) E=(2,1) S=(-1,3) SW=(-3,2) W=(-2,-1)`.
- Forme: **cuneo** (tessera iniziale A al centro (0,0)): posti = `{a·N + b·NE | a,b ≥ 0, a+b ≥ 1}`.
  **Aperta** (tessera B): posti = `{a·N + b·NE} ∪ {a·NE + b·E}` (a,b ≥ 0, non entrambi 0).
  Un posto si può esplorare se è nella forma, è libero, è adiacente ad almeno 2 tessere già piazzate
  oppure (solo tessere Campagna) a una tessera che confina con almeno altre 2 tessere (Regolamento p. 7),
  e il giocatore è su un esagono adiacente a un esagono di quel posto. Le tessere Centrali: almeno 2
  tessere adiacenti e, nel cuneo, mai sulla linea costiera.
  Costo esplorazione 2 punti Movimento; si pesca la tessera in cima al mazzo delle tessere.
- Immagine della tessera (texture 2048×1970 circa): esagoni a punta in alto, raggio ≈ 394 px; centro
  dell'esagono centrale nell'immagine ≈ (1024, 985); i vicini sono a ±√3·r in x e ±1.5·r in y.
  (Il tavolo 3D genera la mesh dei 7 esagoni con le UV ricavate da queste misure.)

## 3. Stato del motore (dizionario serializzabile in JSON)
Tutto lo stato sta in `eng.s` (solo tipi JSON: Dictionary, Array, String, int, float, bool). Niente
riferimenti a nodi. L'RNG ha lo stato dentro `s.rng`. `eng.fingerprint()` = hash dello stato (per l'online).
Campi principali (si possono aggiungere altri campi, documentandoli qui sotto in fondo):
```
s.cfg        configurazione della partita (scenario, giocatori, opzioni, seme)
s.round      1..N     s.day: bool     s.phase: "tactics"|"turn"|"round_end"|"game_over"
s.turn_order [indici giocatori]   s.active: indice del giocatore di turno   s.final_turns: {…}
s.players[i] = {
  hero, name, ctrl: "human"|"ai", ai_level: 1..3, seat (online),
  fame, level, rep (-7..7), armor, hand_limit, command,
  deck:[iid], hand:[iid], discard:[iid], play:[iid], removed:[iid]   # iid = id istanza carta "march#1"
  units:[{uid, id, ready:bool, wounded:bool, used_this_turn…}],
  crystals:{red,blue,green,white}, tokens:[colori]  (gettoni mana, spariscono a fine turno)
  skills:[{id, used_round:bool, used_turn:bool, flipped:bool}], pos:"q,r", tactic:id,
  shields:[hex keys conquistati], fame_track_events…, knocked_out:bool, wounds_this_combat:int
}
s.dummy      giocatore fantoccio (solitario): {hero, deck, discard, crystals, tactic}
s.map = { tiles:[{id, slot:"q,r"}], hex:{ "q,r": {t: terreno, site: tipo|"" , tile, mine:colore,
          enemies:[eid], revealed:bool (per guarnigioni coperte), owner: indice|-1, burned, conquered,
          ruins: token, city:{color, level} } }, tile_deck:[tile ids], shape:"wedge"|"open" }
s.source     [{color, taken_by:-1|i}]  dadi della Fonte
s.offers     {units:[uid id], aa:[card id], spells:[card id], skills:[skill id], monastery:[card id]}
s.decks      {aa:[…], spells:[…], artifacts:[…], units_reg:[…], units_elite:[…], wounds:int}
s.enemy_bags {green:{draw:[eid], discard:[eid]}, gray, brown, violet, red, white, ruins}
s.enemies    {eid: {type: id nemico in enemies.json, color, face_up:bool, hex, …}}   # istanze
s.turn       stato del turno corrente: {player, stage:"move"|"action"|"done", moved, acted,
               pool:{move, influence, heal, attack:{"melee:phys":n, "ranged:fire":n, …}, block:{phys,fire,ice,cold}},
               mods:[modificatori temporanei], dice_taken:int, dice_allowed:int, played:[iid], …}
s.combat     null oppure {enemies:[{eid, defeated, blocked, damage_assigned, …}], phase:
               "ranged"|"block"|"damage"|"attack"|"end", site, fortified, units_allowed, night_rules, …}
s.pending    null oppure decisione in attesa (vedi §4.3)
s.log        [{k: tipo, txt: testo italiano, p: giocatore, …}]   (diario + eventi per l'animazione)
s.result     null | {winner…, scores…}
```

## 4. API del motore (scripts/core/engine.gd, `class_name MKEngine extends RefCounted`)
```
static func create(cfg: Dictionary) -> MKEngine        # nuova partita
static func from_state(s: Dictionary) -> MKEngine      # ripristino (salvataggi, online)
func apply(a: Dictionary) -> Dictionary                # {ok: bool, err: String}; se ok, lo stato cambia
func check(a: Dictionary) -> String                    # "" se l'azione è legale, altrimenti motivo (it)
func actor() -> int                                    # chi deve decidere ora (pending o giocatore attivo); -1 = nessuno
func available() -> Array                              # azioni legali "di alto livello" per actor():
                                                       #   [{a: azione, label: "testo it", group: "card|move|site|combat|turn|unit|skill"}]
func reachable() -> Dictionary                         # {"q,r": costo} esagoni raggiungibili con i punti Movimento attuali (+ pool)
func move_cost(hex) -> int                             # costo dell'esagono adiacente (con modificatori), 999 = invalicabile
func effective_attack(targets: Array) -> int           # attacco efficace del pool contro un gruppo (resistenze)
func effective_block(eid) -> int                       # blocco efficace del pool contro l'attacco del nemico
func fingerprint() -> String
func card(iid) -> Dictionary                           # definizione della carta (da cards.json) per un'istanza
func score(i) -> Dictionary                            # punteggio parziale/finale
```
`cfg = {scenario: "first_recon"|"solo_conquest"|"coop_conquest"|"full_conquest", seed: int,
 players: [{hero:"arythea", ctrl:"human"|"ai", ai_level: 2, name: "Stefano"}], options: {set:"base", city_level: n, …}}`

### 4.1 Azioni (dizionari con campo `t`)
Fase tattiche: `{t:"tactic", id}`.
Turno (giocatore attivo):
- `{t:"play", card: iid, mode: "basic"|"powered"|"side", side: "move"|"influence"|"attack"|"block", mana: [...]?}`
  `mana` opzionale: elenco di fonti `"die:<indice>" | "crystal:<colore>" | "token:<colore>"`; se manca il
  motore sceglie da solo in modo deterministico (gettoni → dadi → cristalli). Carta Azione potenziata = 1 mana
  del colore (oro di giorno vale qualsiasi colore base). Incantesimo base = 1 mana del colore; potenziato =
  1 mana del colore + 1 nero (il nero si usa solo di notte, salvo effetti). Artefatto potenziato = la carta
  viene distrutta (va in `removed`). Laterale = +1 Movimento/Influenza/Attacco fisico/Blocco fisico (ferite mai).
- `{t:"move", to: "q,r"}` — un esagono adiacente (si ripete per spostarsi più volte).
- `{t:"explore", slot: "q,r"}`
- `{t:"unit", uid, ability: int, mana: [...]?}`  `{t:"skill", id, …}`
- `{t:"site"}` inizia l'interazione/l'ingresso nel sito dove si trova (o `{t:"challenge", hexes:[…]}` per
  attaccare nemici scatenati adiacenti). Nel sito: `{t:"recruit", uid}`, `{t:"buy", what:"heal"|"aa"|"spell"|…, id}`,
  `{t:"plunder"}`, `{t:"burn"}` (monastero), `{t:"altar"}` (rovine)…
- `{t:"rest"}` (riposo standard/lento, scelta delle carte tramite pending), `{t:"end_turn"}`,
  `{t:"announce_end"}` (annuncio di fine round quando il mazzo è vuoto a inizio turno).
Combattimento (giocatore attivo, `s.combat != null`):
- carte/unità/abilità come sopra (i punti vanno nel pool del combattimento)
- `{t:"attack", targets: [eid…]}` usa **tutto** il pool d'attacco consentito nella fase contro il gruppo
  (riesce solo se l'attacco efficace ≥ somma delle armature; altrimenti `check` lo rifiuta)
- `{t:"block", eid}` usa **tutto** il pool di blocco contro l'attacco di quel nemico (riesce solo se basta)
- `{t:"damage", eid, to: "hero"|uid}` assegna il danno di un attacco non bloccato (ripetere finché finito)
- `{t:"next"}` passa alla fase successiva del combattimento
Decisioni: `{t:"choose", v: [valori]}` risponde a `s.pending`.

### 4.2 Errori
`apply` non deve mai lanciare eccezioni né lasciare lo stato a metà: valida con `check`, poi applica.

### 4.3 Decisioni in attesa (`s.pending`)
`{type, player, prompt: "testo it", options: [{v: valore, label: "testo it", img?: percorso}], min: 1, max: 1, …}`
Tipi tipici: `choice` (opzioni di un effetto), `card` (scegli carte dalla mano: scarto per Improvvisazione,
riposo…), `offer` (ricompensa: incantesimo/azione avanzata/unità/artefatto), `color` (colore di mana/cristallo),
`skill` (salita di livello: abilità + azione avanzata), `unit`, `enemy`, `hex`, `tactic`.
UI e IA trattano tutte le decisioni con lo stesso schema generico. Le opzioni non disponibili non vanno
proposte (se un'opzione di una scelta non si può applicare, va esclusa; se ne resta una sola si applica da sola).

## 5. DSL degli effetti (carte, unità, abilità, tattiche)
Un effetto è un array `[op, ...]`; una lista di effetti si esegue in ordine. Valori di elemento:
`phys|fire|ice|cold` (cold = fuoco-ghiaccio/coldfire). Tipi d'attacco: `melee|ranged|siege`.
```
["move", n]                ["influence", n]           ["heal", n]
["attack", n, elem?, kind?]   (default "phys", "melee")
["block", n, elem?]           (default "phys")
["fame", n]   ["rep", n]   ["draw", n]
["mana", colore]           gettone mana: red|blue|green|white|gold|black|"basic" (scelta tra i 4 base)
["crystal", colore]        cristallo (max 3 per colore): colore o "basic"; "$paid" = colore appena pagato
["choice", [[effetti…], [effetti…], …]]   il giocatore sceglie un'opzione
["if", condizione, [effetti se vero], [effetti se falso]?]
      condizioni: "day" "night" "combat" "not_combat" "phase:ranged" "phase:block" "phase:attack"
["pay_mana", colore|"basic"|"any", [effetti]]   paga 1 mana (da gettone/dado/cristallo) e poi gli effetti
["discard", n, [effetti]]  scarta n altre carte non-ferita dalla mano, poi gli effetti
["extra_die", n]           può prendere n dadi in più dalla Fonte in questo turno
["ready_unit", livello_max]       ["heal_unit", livello_max]
["boost_next", n]          la prossima carta Azione giocata potenziata ottiene +n ai valori numerici
["terrain", {terreno: costo|"-1"…}]   modifica i costi del terreno per il turno ("-1" = riduzione, min 0/1)
["mod", nome, parametri]   modificatore temporaneo generico (turno o combattimento), vedi specials.json
["special", nome, parametri?]     effetto con nome implementato in scripts/core/specials.gd
```
Ogni carta (cards.json):
```
{ "id": "march", "set": "base", "type": "basic"|"aa"|"spell"|"artifact"|"wound",
  "hero": "" | "arythea"…(per le carte base specifiche dell'eroe; "replaces": id della carta standard sostituita),
  "color": "red"|"blue"|"green"|"white"|"" , "name_it": "Marcia", "name_en": "March",
  "name_powered_it": "…" (solo incantesimi: nome dell'effetto potenziato), "name_powered_en": "…",
  "basic": [effetti], "powered": [effetti], "side": true (si può giocare di lato),
  "combat_only": false, "text_it": {"basic": "…", "powered": "…"}  (testo leggibile per i suggerimenti),
  "img": "assets/cards/march.webp", "copies": 1, "impl": true, "note": "…" }
```
Unità (units.json): `{id, set, elite:bool, name_it, name_en, level, cost, armor, resist:["phys","fire","ice"],
 recruit:["village","keep","mage_tower","monastery","city"], copies, abilities:[{effect:[…], mana: colore|"" ,
 text_it}], img, impl}`.
Abilità (skills.json): `{id, hero, set, name_it, name_en, usage: "turn"|"round"|"passive"|"interactive",
 effect:[…], text_it, img, impl}`.
Tattiche (tactics.json): `{id, day:bool, number, name_it, name_en, effect: [..] o special, text_it, img}`.

**Speciali.** Tutto ciò che il DSL non esprime diventa `["special", "<nome>", {…}]`. Ogni nome usato va
descritto in `data/specials.json`: `{ "<nome>": {"desc": "cosa fa, preciso", "used_by": ["id carta…"]} }`.
Il motore implementa ogni speciale in `specials.gd` (`func sp_<nome>(eng, ctx, params)`); quelli non ancora
implementati rendono `impl:false` la carta (esclusa dal mazzo) finché non vengono fatti.

## 6. Regole (riassunto operativo — fonte: regolamento italiano in /home/claude/work/rules)
Pagine del regolamento rasterizzate: `/home/claude/work/rules/reg-NN.png` (regolamento + libro degli
scenari) e `guida-NN.png` (guida alla prima partita); OCR (inglese, quindi accenti imprecisi) in
`regolamento.txt` / `guida.txt` quando disponibile. In caso di dubbio vale il regolamento.
- **Round**: Giorno/Notte alternati (il primo è Giorno). All'inizio di ogni round: nuovi dadi della Fonte
  (giocatori+2 dadi; almeno metà di colore base: si rilanciano oro/nero in eccesso), scelta delle tattiche
  (in ordine inverso di Fama; il fantoccio sceglie a caso dopo il giocatore in solitario), ordine di turno =
  numero della tattica. Rinnovo delle offerte di unità/azioni avanzate/incantesimi a fine round.
- **Turno**: o **riposo** (standard: scarta 1 carta non-ferita + qualsiasi numero di ferite; lento: se in mano
  hai solo ferite, scartane 1) oppure movimento (+esplorazione) e poi **una** azione (interazione in un sito,
  combattimento, ecc.). Fine turno: gettoni mana spariti, dadi rilanciati e restituiti, carte giocate e
  scartate nella pila degli scarti, si pesca fino al limite di mano (+1 se su/adiacente a una propria
  fortezza conquistata, oppure +bonus città), salita di livello, ricompense.
- **Mana**: 1 dado della Fonte per turno (oro = qualsiasi colore base di giorno, inutilizzabile di notte; nero =
  utilizzabile solo di notte e solo per incantesimi potenziati). Cristalli (max 3 per colore) usabili come mana;
  gettoni mana temporanei.
- **Movimento** (costi Giorno/Notte): pianura 2/2, colline 3/3, foresta 3/5, deserto 5/3, landa desolata 4/4,
  palude 5/5, città 2/2; lago, montagna, oceano invalicabili. Non si entra in esagoni con nemici scatenati
  né in esagoni con altri eroi (salvo regole).
  **Provocazione**: passare da un esagono adiacente a un nemico scatenato a un altro esagono adiacente allo
  stesso nemico provoca il combattimento (il movimento finisce). Entrare in un sito fortificato (fortezza,
  torre magica, città) non conquistato = assalto (reputazione −1) e combattimento con la guarnigione.
- **Siti**: villaggio (reclutare, guarire 3 Influenza = 1 Guarigione, saccheggio rep −1 pesca 2 carte),
  monastero (reclutare, guarire 2 Influenza = 1, comprare l'azione avanzata del monastero per 6, incendiare:
  rep −3 e combattimento con un nemico viola, ricompensa artefatto), fortezza (guarnigione grigia;
  conquista → scudo; poi reclutare), torre magica (guarnigione viola; conquista → incantesimo; poi comprare
  incantesimi a 7 Influenza + 1 mana del colore), dungeon (nemico marrone pescato all'ingresso, niente unità,
  regole notturne per il mana; ricompensa: tira un dado: oro/nero = artefatto, altrimenti incantesimo),
  tomba (nemico rosso, niente unità, regole notturne; ricompensa incantesimo + artefatto), tana dei mostri
  (nemico marrone, ricompensa 2 cristalli tirati), terreno di nidificazione (2 marroni, artefatto + 3
  cristalli), rovine antiche (segnalino giallo: altare = paga 3 mana del colore → 7 Fama, oppure nemici +
  ricompensa), radura magica (inizio turno: gettone oro di giorno / nero di notte; fine turno: scarta una ferita
  dalla mano o dagli scarti), miniera di cristalli (fine turno: un cristallo del colore della miniera), città
  (guarnigione bianca e altre secondo livello; conquista; poi interazioni della città).
  Controllare sul regolamento le ricompense esatte e le eccezioni (es. dadi, scelta dall'offerta, fama).
- **Combattimento**: fasi *Attacco a distanza/assedio* → *Blocco* → *Assegnazione dei danni* → *Attacco*.
  Fortificato: in fase a distanza solo assedio. Resistenze: l'attacco/blocco "inefficace" vale metà
  (arrotondato per difetto, sommando prima tutte le parti inefficaci). Blocco efficiente: contro fuoco solo
  ghiaccio (o fuoco-ghiaccio), contro ghiaccio solo fuoco (o fuoco-ghiaccio), contro fuoco-ghiaccio solo
  fuoco-ghiaccio; contro fisico tutto è efficiente. Rapido: per bloccare serve il doppio. Brutale: danno
  raddoppiato. Velenoso: ogni ferita all'eroe ne aggiunge una negli scarti; unità avvelenata = 2 ferite
  (distrutta). Paralizzante: unità ferita = distrutta; eroe ferito = scarta tutte le carte non-ferita dalla
  mano. Evocatore: in fase di blocco pesca un nemico marrone che attacca al suo posto. Danno all'eroe: ferite =
  ⌈danno/armatura⌉ in mano. Danno a un'unità: l'unità assorbe danno pari alla sua armatura e viene ferita
  (se resistente all'elemento: prima riduce il danno della sua armatura senza ferirsi, poi se resta danno si
  ferisce e lo riduce di nuovo). **KO**: se in un combattimento ricevi in mano ferite ≥ limite di mano
  (base), scarti subito tutte le carte non-ferita. Fama per ogni nemico sconfitto. Le unità ferite non si usano;
  le unità esaurite si preparano a fine round.
- **Livelli** (Fama necessaria): 1:0 2:3 3:8 4:15 5:24 6:35 7:48 8:63 9:80 10:99. Livelli 1–2: armatura 2,
  mano 5, comando 1; 3–4: 3/5/2; 5–6: 3/6/3; 7–8: 4/6/4; 9–10: 4/7/5. Ai livelli pari (2,4,6,8,10) si sceglie
  un'abilità (tra 2 pescate dalla propria pila + l'offerta comune in competitiva) e un'azione avanzata
  dall'offerta (in cima al mazzo).
- **Reputazione** (−7..+7) → bonus all'Influenza nelle interazioni: −7: nessuna interazione, −6:−5, −5:−3,
  −4:−2, −3:−1, −2:−1, −1:0, 0:0, 1:0, 2:+1, 3:+1, 4:+2, 5:+2, 6:+3, 7:+5.
- **Fine round**: chi a inizio turno ha il mazzo vuoto può annunciare la fine del round; gli altri fanno
  un ultimo turno. Fine partita secondo lo scenario (numero di round o obiettivo).
- **Punteggio** (competitiva/fine): Fama + titoli (Massima Conoscenza, Massimo Bottino, Massimo Comandante,
  Massimo Conquistatore, Massimo Avventuriero, Massime Ferite…) come da regolamento.
- **Fantoccio** (solitario): mazzo delle 16 carte base di un eroe non usato + 3 cristalli del suo colore;
  a ogni suo turno gira 3 carte; se l'ultima ha il colore dei suoi cristalli ne gira tante in più quanti sono
  i cristalli di quel colore; con il mazzo vuoto annuncia la fine del round. A fine round prende l'azione
  avanzata e l'incantesimo più in basso nelle offerte (cristallo del colore dell'incantesimo).

## 7. Asset (prodotti dagli script in `tools/` del repo, a partire dai file del modulo TTS)
File sorgente del modulo nel container: `/mnt/user-data/uploads/Mage Knight/Mods/Images/<cache>.jpg|png` e
`/Mods/Models/<cache>.obj`, dove `<cache>` = URL con i soli caratteri alfanumerici. Le URL stanno nel JSON del
modulo `/home/claude/work/mod.json` (campi `{en}url{it}url…`: usare la versione `{it}`, altrimenti `{en}`).
Manifesto degli oggetti già estratto: `/home/claude/work/objs.json` (guid, nickname, path, img, face, nw,
nh, idx, mesh, diffuse…). Lua globale: `/home/claude/work/global.lua` (tabelle `gameCards`, `terrainTiles`,
`monsterPugs`, `skillTokens`, `mageKnights`, `GUID`, `scenarioList`…).
Uscite (immagini per il web: WebP qualità ~85, lato max ragionevole):
```
assets/tiles/<tile_id>.webp            texture delle tessere (front)
assets/enemies/<enemy_id>.webp         fronte dei segnalini nemico;  assets/enemies/back_<colore>.webp
assets/ruins/<ruin_id>.webp
assets/cards/<card_id>.webp            una carta per file (anche unità, tattiche, ferite, retro)
assets/skills/<skill_id>.webp
assets/models/<nome>.obj + texture     eroi, città, ecc.
assets/miniatures/<id>.glb             (facoltativi) miniature Meshy che sostituiscono le sagome
data/assets.json                       manifesto id → percorso
```

## 8. Interfaccia (seconda ondata)
Menu (scenario, eroi umani/IA, livello IA, gioco online), tavolo 3D (mappa ruotabile/zoomabile come BEAST),
HUD con mano, area di gioco, Fonte, cristalli/gettoni, unità, pannello del combattimento, offerte, diario,
regole in breve, zoom delle carte al passaggio del mouse, passa-dispositivo in hotseat.

## Appendice: campi di stato aggiunti
(chi aggiunge campi a `s` li elenca qui)

### Motore (agente ENGINE) — `scripts/core/*.gd`, `scripts/data/db.gd`
File: `rng.gd` (MKRng), `hexmap.gd` (MKHex), `mana.gd` (MKMana: fonti di mana e pagamenti), `effects.gd` (MKEffects:
interprete del DSL), `combat.gd` (MKCombat), `sites.gd` (MKSites: siti, interazione, ricompense, conquista, salita di
livello, tattiche), `specials.gd` (MKSpecials: speciali `sp_<nome>`, mod, azioni speciali, hook), `avail.gd` (MKAvail:
`available()`), `engine.gd` (MKEngine). `eng.clone()` = copia profonda di `s` per la lookahead dell'IA.
`MKEngine.sanitize(a)` normalizza i tipi dei campi delle azioni (numeri da JSON → int; campi errati → rifiuto).

**Azioni aggiunte** (oltre a §4.1): `{t:"heal", target:"hand"|uid}` (spende punti Guarigione del pool),
`{t:"recruit", id, disband?:uid}`, `{t:"buy", what:"heal"|"aa"|"spell"|"aa_offer"|"aa_top"|"artifact"|"elite", id?, mana?}`,
`{t:"altar", mana?}`, `{t:"disband", uid}`, `{t:"tactic_use", opt}` (tattiche attivabili: right_moment, long_night,
mana_search, meditation, store/take = Risparmiare Potere), `{t:"sp", name, …}` (azioni speciali generate da effetti
giocati: move_to_attack, influence_as_block, buy_aa_with_influence, influence_to_heal, ready_units_for_influence,
wound_sideways, banner_fear, banner_ready). `{t:"damage", eid, attack?, to}`, `{t:"block", eid, attack?}` (indice
dell'attacco per i nemici con più attacchi). Le decisioni in sospeso sono **sempre a scelta singola** (`v:[valore]`);
le scelte multiple sono iterative con un'opzione "Basta così"/"Fine".
Regola "gioca o scarta almeno una carta": se a fine turno non hai giocato/scartato nulla e hai carte non-Ferita, il
motore chiede quale scartare; con sole Ferite in mano e nulla giocato puoi solo riposare.

**Stato `s` (campi aggiunti)**
```
s.v, s.rng:int, s.order_pos, s.announced_by:-1|i|9, s.game_end_pending:bool, s.final_turns:{"<i>":true}
s.eid_seq, s.iid_seq, s.uid_seq, s.log_seq
s.tactics_avail:[id], s.tactics_removed:[id], s.tactic_pick:[i] (ordine di scelta), s.core_revealed, s.cities_revealed
s.scn = scenario risolto {id, name_it, rounds, shape, cols, country, core, city, city_levels:[..], mode:"solo"|"coop"|
        "competitive", dummy, end:"cities"|"city_revealed", cities_enterable, elite, fame_per_tile, start_fame, start_rep,
        fame_line_bonus, extra_die, extra_unit, tactics_removed_solo, dummy_first, remove_one_tactic, dummy_no_final,
        titles, scoring, score_extra, sets}
s.map.portal, s.decks.tiles_spare, s.decks.wounds (contatore)
giocatore fantoccio: indice 9 (MKEngine.DUMMY) in turn_order; s.dummy = {hero, name, deck, discard, crystals, tactic, skill_pile}
s.players[i] += skill_pile, tactic_used, tactic_store (Risparmiare Potere), stolen_die (Rubare Mana),
   pending_hand_bonus, spells_cast, turns, finished, banners:{"<uid>": iid} (Stendardi assegnati), banner_used,
   mana_claim_color, frozen_die, set_aside (carte messe da parte fino a fine round), bonds_discount, extra_command
   units[] = {uid, id, ready, wounded, wounds:1|2 (veleno), extra_resist?}   skills[] = {id, used_round, used_turn, flipped}
s.map.hex[k] = {t, site, tile, mine, mines?, enemies:[eid], owner, conquered, burned, ruins:id, ruins_face_up,
   rampage:bool (esagono di nemici scatenati), revealed, city?:{color, level, shields:[i,…] in ordine, leader}}
s.enemies[eid] = {type, color, face_up, hex, half_fame?}
s.turn += started, rested, interacted, rep_applied, prev, path:[hex], ending, end_step, plundered, destroy:[iid]
   (artefatti potenziati), set_aside, explored, combats, discarded, extra_turn, skip_draw, fixed_dice:[i],
   crystals_spent, wounds_received, block_swift, block_per_ability, stolen_used, search_used, sparing_done,
   no_final_consume, rewards:[{k:"spell"|"aa"|"aa_lowest"|"artifact"|"unit"|"crystal_roll"(n)|"crystals4"|"crystals"|
   "fame"|"dungeon_roll"}] (date a fine turno), mods:[{name, src, p, …parametri}]
   (mod usati dal motore: terrain{map}, attack_bonus/block_bonus{n,kind?,elem?,src_kind?}, side_value, armor,
   unit_armor, hand_limit, recruit_discount, no_dice, gold_ok, black_ok, no_provoke, space_bending, …)
s.combat = {enemies:[{eid, type, name, armor, armor_mod, fame, resist, abilities, lost, lost_resist, self_fort, site_fort,
   self_fort_lost, site_fort_lost, fortified, dfort, attacks:[{n, elem, elem_override?, mod, blocked, rem, units_hit}],
   defeated, site_def, summoned, by, hidden, rampage, half_fame, no_attack, no_fame, color, rep}],
   phase:"ranged"|"block"|"damage"|"attack"|"end", site, site_type, kind:"assault"|"provoke"|"challenge"|"site"|"burn",
   assault, retreat, units_allowed, night_rules, wounds_hand, fame, fortified_site, city, ruins, first_time, summoned,
   blocked_count, delayed:[{n,elem}], units_absorbed}
s.pending = {type, player, handler, prompt, options:[{v, label, img?}], min:1, max:1, data, queue, ctx}
s.log[] = {k, txt, seq, p?, …} (seq crescente; il diario tiene le ultime ~300 voci). Tipi k principali: setup, round,
   order, turn, tactic, play, pts, mana, move, reveal, reveal_enemy, reveal_ruins, city, provoke, assault, challenge,
   enter_site, combat_start, combat_phase, attack, block, enemy_defeated, summon, wound, unit_wound, unit_destroyed,
   unit_absorb, knockout, combat_end, conquer, retreat, fame, rep, level, skill_gain, gain_card, recruit, disband, heal,
   draw, discard, rest, dummy, announce, round_end, game_end, game_over, roll, info, error
s.result = {scores:[{fame, achievements:{knowledge,loot,leader,conqueror,adventurer,beating}, titles, cities, objective,
   total}], winners:[i], rounds, cities_conquered?, cities_total?, victory?, team_score? (cooperativo)}
```
**Carte non implementate**: `MKDB.card_ok(id)/unit_ok/skill_ok` sono false se la carta ha `impl:false` o usa un
`special`/`mod` assente da `MKSpecials.implemented()`; tali carte/unità/abilità non entrano in mazzi e offerte.

### Combattimento tra giocatori e assalto cooperativo (agente PVP-COOP) — `scripts/core/pvp.gd`, `coop.gd`, `ai_pvp.gd`
Regolamento p. 12–13 (e p. 6–8 per spazi condivisi, gettone Ordine di Round, Ritirata Forzata).

**Opzione**: `cfg.options.pvp` (bool). Predefinito: sì negli scenari competitivi tranne *Prima ricognizione*
(`MKPvP.enabled`). Nei cooperativi non c'è mai combattimento tra giocatori.

**Azioni**: `{t:"pvp_attack"}` (giocatore di turno, nello spazio di un altro eroe: è la sua azione),
`{t:"pvp", op:"strike"|"pass"|"block"}`, `{t:"coop", city:"q,r"}` (proposta di assalto cooperativo).
Decisioni: `pvp:mode` (difensore: `"full"`|`"partial"`), `pvp:hit` (attaccante: `"hero"`, `"u:<uid>"`, `"a:<iid>"` =
ruba Artefatto, `"<q,r>"` = costringi alla ritirata e vinci, `"done"`), `coop:invite` (`"j,k"`|`"cancel"`),
`coop:split` (`"2,1"` = nemici per partecipante nell'ordine della proposta | `"cancel"`), `coop:accept` (`"yes"|"no"`,
`player` = invitato).

**Stato**
```
s.players[i].skip_next: bool      gettone Ordine di Round a faccia in giù: il prossimo turno viene saltato
                                  (difensore che ha affrontato completamente, invitati di un assalto cooperativo)
s.pvp = null | {att, def, mode:"full"|"partial", phase:"ranged"|"melee", step:"mode"|"attack"|"block"|"hit"|"after",
   striker, passes, strike:{n, elems:[…], by}|null, dmg, saved: turno (s.turn) di chi NON sta agendo, from: spazio da
   cui l'aggressore ha attaccato, hex, fort (difensore in castello/torre: a distanza solo Assedio), result, winner, log_from}
   s.combat = {kind:"pvp", pvp:true, phase:"ranged"|"block"|"attack", enemies:[] …} durante gli scambi
s.turn += pvp_side | coop_side (turno "anticipato" del difensore / dell'invitato), no_final_consume, coop_tries
s.coop_prop = null | {city, init, members:[…], split:[…], idx}          proposta in corso
s.coop = null | {city, init, order:[giocatori in ordine di round da chi inizia], groups:{"i":[eid]}, from:{"i":hex},
   idx, stage:"combat"|"end", saved:{"i": turno sospeso}, log_from}
s.combat.coop = true             combattimento di un partecipante (kind "assault"): conquista/ritirata decise alla fine
```
**Combattimento tra giocatori**: i due turni si alternano in `s.turn` (quello inattivo sta in `s.pvp.saved`, mai due
riferimenti allo stesso dizionario), così le carte/unità/abilità di ciascuno vanno nel proprio pool. Fase a distanza
(inizia il difensore; contano solo `ranged`/`siege`, solo `siege` se l'aggressore attacca il difensore fortificato; il
Blocco efficiente se lo è contro almeno un elemento dell'attacco; riduzione = metà del blocco totale) poi corpo a corpo
(inizia l'aggressore; tutti gli attacchi, carte di lato = Attacco fisico 1; riduzione = blocco totale). Due "passa"
consecutivi chiudono la fase; nel corpo a corpo = parità (l'aggressore torna nello spazio da cui ha attaccato). Danni:
servono danni ≥ Armatura (unità: doppia se resistente a un elemento dell'attacco) per ogni Ferita; nel corpo a corpo 5
danni rubano un Artefatto (scarti, area di gioco, Stendardo di un'unità ferita) e il costo di terreno non modificato
di uno spazio sicuro adiacente costringe alla ritirata (vittoria; Fama 1 + 2 per livello in meno, oppure 1 a pari
livello con meno Fama). KO come nel combattimento normale. *Completo*: il difensore usa un dado e le Abilità, poi
completa il turno (`step:"after"`: cure/effetti, fine turno con pesca) e `skip_next`. *Parziale*: niente dado né
Abilità (salvo interattive), le carte giocate vanno negli scarti, nessuna pesca, i gettoni mana restano.
Fine turno nello spazio di un altro eroe = attacco automatico (`MKPvP.auto_attack`); se non consentito, Ritirata
Forzata come prima. Entrare nel castello di un avversario presente = assalto (Reputazione −1) + combattimento tra
giocatori. Non si entra nello spazio di un eroe con un movimento che provoca nemici scatenati. In uno spazio con un
altro eroe (non portale/città conquistata) niente azioni di sito/sfide/interazione.
**Assalto cooperativo**: proponibile da chi non ha ancora agito, adiacente a una città non conquistata (≥ 2 difensori),
senza altri eroi nel suo spazio, con alleati disponibili (adiacenti, gettone a faccia in su, almeno una carta
non-Ferita). Accettato da tutti: invitati `skip_next`, difensori mescolati e distribuiti (MKRng). In ordine di round da
chi inizia, ogni partecipante entra in città gratis (Reputazione −1, provoca i nemici scatenati come un movimento
normale) e combatte solo il suo gruppo con un turno proprio (`coop_side`, un dado della Fonte). Poi: tutti i difensori
sconfitti = città conquistata (capo = più Scudi, a parità il primo Scudo), altrimenti tutti tornano allo spazio da cui
hanno attaccato; infine ciascuno, in ordine, termina il turno (cure, ricompense, livelli, pesca). Hook nel motore:
`_resume_loop` (→ `MKCoop.after_combat`), fine turno passo 6 (`MKPvP.sub_turn_end`, `MKCoop.sub_turn_end`),
`_start_player_turn` (`MKPvP.skip_turn`), `check` (`MKPvP.gate`).
`wounds_only_lock` ora vale solo finché il giocatore non si è mosso né ha agito (prima, dopo un combattimento senza
carte giocate e con sole Ferite in mano, il turno non poteva più finire).
**IA** (`ai_pvp.gd`): attacca un avversario raggiungibile solo se la mano basta con margine (Normale/Difficile) e c'è
Fama da guadagnare o l'avversario è in testa; da difensore sceglie *parziale* (salvo mano quasi vuota); negli scambi
gioca le carte con il miglior rapporto punti/valore; assegna i danni preferendo eroe + ritirata. In cooperativa propone
l'assalto se la forza stimata della squadra copre la guarnigione, si avvicina a una città dove un alleato aspetta,
accetta se ha abbastanza carte, divide i nemici in proporzione alla forza.
UI: `scripts/ui/pvp_panel.gd` (pannello centrale con i due eroi; agisce `eng.actor()`, in hotseat prima compare
*Passa il dispositivo*), bottoni «⚔ Attacca …» e «⚑ Proponi un assalto cooperativo…» fra le azioni, nota e titolo
«Assalto cooperativo» nel pannello del combattimento, gettone a faccia in giù (⤓) nella barra dell'ordine, opzione
*Combattimento tra giocatori: Sì/No* nel menu (Conquista Totale). Test: `tests/pvp_test.gd`, screenshot `tests/pvp_ui.gd`.
### Espansioni (agente EXPANSIONS) — `scripts/core/specials_exp.gd`, `combat_exp.gd`, `sites_exp.gd`
**Contenuti.** `cfg.options.content`: `"base"` | `"ll"` | `"tezla"` (cumulativi) → `MKDB.CONTENT_SETS`:
base = `["base"]`; ll = `["base","ll","ue","promo","krang"]`; tezla = ll + `"tezla"` (`options.sets` esplicito ha la
precedenza; i set `fan` e `apocalypse` restano fuori). Un eroe porta sempre le sue carte base e le sue abilità, qualunque
sia il contenuto. Tessere usate: Campagna 12–14 e Centrali 9–10 (l'accampamento di Volkare e le tessere Apocalypse
Dragon restano escluse da `_tile_supported`).
**Moduli.** `MKSpecialsExp` (speciali delle espansioni + hook del motore; `MKSpecials.obj(metodo)` cerca prima in
specials.gd e poi in specials_exp.gd, quindi `sp_/can_/res_` funzionano allo stesso modo), `MKCombatExp` (abilità dei
nemici: Elusivo, Difensore, Ingombrante, Assassinio, Vampirico, Evocatore multiplo, mura, Unità unica nel dedalo, attacchi
a bersaglio singolo, Attirare il fuoco), `MKSitesExp` (Campo Profughi, Dedalo/Labirinto, testo delle regole delle
espansioni per la schermata Regole).
**API.** `move_cost(hk, from := "")` (+1 se c'è un muro tra `from` e `hk`; `MKSpecialsExp.space_cost` applica Sentieri
Druidici), `has_wall(a, b)`, `MKEngine.wall_key(a, b)`, `rampage_threatens(esagono_nemico, verso)`. `MKCombat.armor_of` =
`MKCombatExp.armor_full` (armatura elusiva/vampirica/difesa ricevuta + bonus Difensore potenziale, prudente per l'IA);
il controllo dell'attacco usa `armor_core` + `defend_extra` (valore esatto per il gruppo).
**Azioni aggiunte** `{t:"sp", name:…}`: `cumbersome` {eid, attack} (spendi 1 Movimento: attacco −1, a 0 = bloccato),
`maze_path` {cost: 2|4|6}, `chaos_rotate` (Signore del Caos: rotazione gratuita a inizio turno), `enh_token` (prendi il
gettone di Potenziamento del Mana di un alleato), `nv_coop` {eid} (Vendetta della Natura cooperativa).
**Dati.** `MKDB.enemies[id]` += `elusive_armor`, `faction`, `summon_n` (Evocatore di Draghi = 2); `MKDB.tiles[id].walls`
= {dirkey: [dirkey…]} (muri interni alla tessera).
**Stato `s` (campi aggiunti)**
```
s.map.walls = {"k1|k2": true}                         muri sulla mappa (chiavi ordinate)
s.map.hex[k].maze_paths = {"2"|"4"|"6": i}           sentieri conquistati di Dedalo/Labirinto
s.inter = [{id, owner, mode, …}]                       parte "per gli altri" delle abilità interattive (Ululato,
        Soppressione/Potenziamento del Mana {colors, hit | color, taken}, Vendetta della Natura {used_by});
        tolta all'inizio del turno successivo del proprietario
s.familiars_q = [[i, uid]]                             mantenimento dei Famigli Magici a inizio round
s.turn += maze {hex, stage:"unit"|"pay"|"fight", unit, cost}, recruited_uids, defeated_types, basic_spent,
          box_revealed, box_used, chaos_rot
s.players[i] += kept_enemies:[tipo] (Burattinaio); units[] += token (Famigli Magici);
          skills[] += chaos, chaos_last, chaos_free (Signore del Caos)
s.combat += units_only (uid dell'unica Unità ammessa nel dedalo); enemies[] += elusive_armor, vamp, defend_bonus,
          defend_used, tbonus:[{n, elem, kind}] (attacchi a bersaglio singolo); attacks[] += draw_fire (Truppe d'Assalto)
```
Mod nuovi in `s.turn.mods`: `wolfs_howl{n}`, `mana_enhancement`, `shapeshift{from,to,card}`, `crystal_on_move{times,used}`,
`reduce_space_cost{n,min,terrain,hex}`, `banner_command`. Correzione: alla salita di livello il Comando tiene conto di
`extra_command` (Legami di Lealtà).
