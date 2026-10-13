# Mage Knight — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Mage Knight** (Vlaada Chvátil, WizKids), Ultimate Edition:
gioco base, eroi delle espansioni (Wolfhawk, Krang, Braevalar) e, a scelta, i contenuti di *La Legione
Perduta* e *Shades of Tezla*. Componenti, illustrazioni e regole © dei rispettivi autori: le immagini vengono dal modulo
Tabletop Simulator «Mage Knight Plus (Highly Scripted)» e non vanno distribuite pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/Mage-Knight/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**.

## Cosa c'è
- **Scenari**: *Prima Ricognizione* (introduttivo), *Conquista in solitario* (con il giocatore Neutrale),
  *Cooperazione Totale* (2–3 eroi contro le città), *Conquista completa* (competitiva, 2–4 eroi,
  città di livello 4) e le varianti Blitz.
- **Eroi**: Arythea, Goldyx, Norowas, Tovak, **Wolfhawk**, **Krang** e **Braevalar** (con le loro carte base,
  tutte le abilità comprese quelle interattive, figure 3D e ritratti). Ogni posto può essere **Umano** o **IA**
  (Facile, Normale, Difficile); più umani sullo stesso dispositivo giocano a turno con la schermata *Passa il
  dispositivo*.
- **Contenuti** (nuova partita): *Base*, *+ La Legione Perduta* (tessere Campagna 12–14 e Centrali 9–10 con
  Campo Profughi, Dedalo, Labirinto, Miniere Profonde e mura; nemici con Elusivo, Ingombrante, Assassinio,
  Immunità arcana, Reputazione alla sconfitta, Evocatore di Draghi; Azioni Avanzate, Incantesimi, Artefatti,
  Unità – Esploratori, Teppisti, Truppe d'Assalto, Famigli Magici, Stregoni, Maestri Delphana, Eroi – e Rovine
  dell'espansione; più le carte Ultimate Edition e il Forziere Misterioso) oppure *+ Shades of Tezla* (in più i
  nemici di Tezla: Vampirico, Difensore…). Vedi *Espansioni* più sotto.
- **Regole complete del gioco base**: Giorno/Notte, Riserva di mana con dadi, cristalli e gettoni,
  tattiche, movimento ed esplorazione, nemici scatenati e provocazione, tutti i siti (villaggi,
  monasteri, castelli, torri della magia, sotterranei, tombe, tane, terreni di nidificazione, antiche
  rovine, radure, miniere, città), combattimento in quattro fasi con fortificazioni, resistenze,
  efficienza degli elementi, Rapido, Brutale, Velenoso, Paralizzante ed Evocatore, unità, ferite e KO,
  riposo, livelli con abilità e azioni avanzate, reputazione, fine round, punteggio con i titoli.
- **Tutte le carte in italiano**: azioni base (ricostruite in italiano dalle immagini inglesi del
  modulo, l'unico mazzo che mancava), azioni avanzate, incantesimi, artefatti, unità, abilità, tattiche,
  con il testo leggibile allo zoom.
- **Mappa 3D** ruotabile e zoomabile: le tessere del modulo, le figure degli eroi e delle città, i
  segnalini dei nemici con le **miniature 3D generate con Meshy** (tutti i 29 tipi di nemico del gioco
  base, più villaggio, monastero, castello e torre della magia). Si possono spegnere dal menu di gioco
  (*Miniature 3D: Sì/No*).
- **Salvataggio automatico**: dal menu, *Continua partita*.

## Espansioni
Regole implementate (dalle carte descrizione sito italiane del modulo per Campo Profughi, Dedalo, Labirinto,
Miniere Profonde e Mura; il resto dal regolamento dell'espansione a memoria):
- **Mura**: attraversarle costa 1 Movimento in più (gli sconti sul terreno non lo tolgono, i movimenti speciali
  degli effetti sì); niente provocazione attraverso un muro; sfida attraverso un muro = nemici fortificati;
  assalto attraverso un muro = guarnigione fortificata doppia.
- **Campo Profughi**: si recluta qualsiasi Unità dell'offerta, +0 se si recluta al villaggio, +1 se al castello /
  torre / monastero, +3 se solo in città (vale l'opzione più conveniente).
- **Dedalo / Labirinto**: una sola Unità al seguito, Movimento 2/4/6 generato dopo essere entrati, nemico
  marrone/rosso scartato comunque; ricompense 2 cristalli / Incantesimo / Artefatto (+ Azione Avanzata nel
  Labirinto); ogni sentiero una volta, ogni eroe una volta per sito. **Miniere Profonde**: colore a scelta.
- **Nemici**: Elusivo, Difensore, Ingombrante (si spende Movimento nella fase di Blocco), Assassinio, Vampirico,
  Immunità arcana, Evocatore di Draghi (due mostri), Teppisti/Eroi (Reputazione ±1).
- **Abilità interattive**: la parte del proprietario si applica subito; quella per gli altri giocatori resta in
  gioco fino al suo turno successivo (Ululato del Lupo: Unità avversarie −1; Ululato del Branco: il prossimo
  alleato che combatte toglie 1 Armatura e 1 attacco a un nemico; Vendetta della Natura: attacchi nemici +1 in
  fase di Blocco per gli avversari / stesso effetto per un alleato; Soppressione del Mana: il primo mana base
  degli avversari costa un mana in più, poi Krang prende un cristallo; Potenziamento del Mana: cristallo per Krang
  e gettone per un alleato).
- **Esclusi**: tessere e scenari di Volkare (accampamento di Volkare), tessere *Apocalypse Dragon*, contenuti
  dei fan; le ricompense di fazione dei nemici di Tezla (servono solo negli scenari delle fazioni). Le basi
  Meshy dei nuovi nemici non ci sono ancora: si vedono i segnalini.
- L'IA usa i nuovi eroi, carte, Unità e nemici e recluta al Campo Profughi; non entra nei Dedali/Labirinti.

## Comandi
- **Telecamera**: tasto destro trascinato = ruota e inclina; rotella o pizzico = zoom; sinistro
  trascinato = sposta; Q/E ruota, R/F inclina, WASD sposta, +/− zoom, Home vista iniziale; pulsanti sullo
  schermo per il telefono.
- **Mano**: clic su una carta → Base, Potenziata (con la scelta del mana), Di lato. Passa il mouse per
  ingrandirla.
- **Mappa**: gli esagoni raggiungibili sono evidenziati con il costo; clic per muoversi (anche più
  esagoni). Le tessere esplorabili si illuminano; provocazioni e assalti chiedono conferma.
- **Combattimento**: pannello con le quattro fasi; seleziona i bersagli, gioca le carte e premi
  *Attacca*/*Blocca*; poi assegna i danni a eroe o unità.

## Intelligenza artificiale
Pianificatore per turno: valuta gli obiettivi raggiungibili (siti, nemici, reclutamenti, esplorazione,
assedio delle città su più turni) stimando con la mano, le unità e il mana cosa può davvero vincere, poi
gioca le carte con simulazioni sul motore. In media gli eroi IA arrivano al livello 6–7 (Difficile).
Le città restano difficili per l'IA: le conquista di rado, soprattutto in solitario.

## Gioco online

Si gioca in rete con gli amici, ognuno dal proprio dispositivo (anche dal browser), con lo stesso
sistema di Kingsburg: **lockstep** su Firebase (progetto `flammerouge-f8669`, accesso anonimo, nessuna
registrazione).

**Come si gioca**
1. In *Nuova partita* scegli scenario ed eroi: i posti **UMANO** diventano posti per le persone (il
   primo è il tuo), i posti **IA** restano dell'IA.
2. *Gioca online* → scrivi il tuo nome → **Crea una stanza**: compare un codice di 4 lettere.
3. Gli amici aprono *Gioca online*, scrivono il loro nome e il codice → **Entra**. Nella stanza si vede
   chi occupa ogni posto.
4. Chi ha creato la stanza preme **Inizia online**. I posti UMANO rimasti liberi li gioca l'IA.

**Come funziona**
- Tutti i dispositivi fanno girare lo stesso motore con la stessa configurazione e lo stesso seme;
  sul database viaggiano solo le azioni, numerate (`mageknight/rooms/<codice>/acts/0, 1, 2…`). Ogni
  azione si scrive una volta sola (la prima che arriva vale) e tutti la applicano nello stesso ordine.
- Gli eroi IA e i posti liberi li gioca il dispositivo di chi ha creato la stanza (l'host): se l'host
  esce, l'IA si ferma finché non rientra.
- Se un giocatore non risponde per un minuto, l'host lo segna *assente* e al suo posto gioca l'IA;
  quando torna riprende il suo eroe.
- **Rientro**: chi chiude la pagina o perde la connessione riapre *Gioca online* e preme *Rientra
  nella stanza* (oppure scrive lo stesso codice e lo stesso nome): il gioco scarica tutte le mosse e
  le rigioca ("Ricollegamento…"), poi si continua. Nel browser l'identità è legata alla scheda;
  da un altro dispositivo si può riprendere il proprio posto con lo stesso nome dopo che è stato
  segnato assente.
- **Controllo della sincronia**: ogni 20 mosse l'host scrive l'impronta dello stato
  (`fp/<n>`); gli altri la confrontano con la propria e, se diverge, ricostruiscono la partita
  rigiocando tutte le mosse.
- **Mani "segrete"**: in lockstep ogni dispositivo conosce lo stato completo, comprese le carte in
  mano agli altri. L'interfaccia non le mostra, ma chi volesse barare smontando il programma potrebbe
  vederle: è un gioco tra amici.
- Con la rete instabile il gioco riprova da solo ("Rete non raggiungibile, riprovo…").

**Per chi gestisce il progetto Firebase**: le regole del database sono in
`firebase/database.rules.json` (il file completo, con le sezioni degli altri giochi e la nuova
sezione `mageknight`). Vanno pubblicate dalla console di Firebase (*Realtime Database → Regole*,
incollare tutto il file → *Pubblica*) oppure con `firebase deploy --only database`.

**Prove in locale**: `tests/online_play.sh` avvia un finto Firebase (`tests/firebase_mock.py`, che
applica davvero le regole) e due istanze del gioco senza grafica (host e ospite): partita completa,
l'ospite esce a metà e rientra, poi una partita in cui l'ospite si desincronizza di proposito. Alla
fine le impronte delle partite devono coincidere. `MOCK_FLAKY=0.08 tests/online_play.sh` simula una
rete che perde l'8% delle richieste. Nel browser si può puntare al finto Firebase con
`index.html?mkdb=http://127.0.0.1:8765/db`.

## Miniature 3D (Meshy)
Le miniature sono in `assets/miniatures/<id>.glb` (un file per tipo di nemico o di sito): il gioco le
appoggia da solo sul tavolo, senza modifiche al codice. Per generarne altre (per esempio i nemici delle
espansioni) vedi `meshy/LEGGIMI.md`: `python3 meshy/genera_miniature.py` con la chiave `MESHY_API_KEY`
oppure dopo `meshy auth login --device`; lo script comprime da solo i modelli per il web.

## Struttura
```
data/*.json               tessere, nemici, rovine, città, tattiche, regole, scenari, eroi, carte, unità,
                          abilità, speciali (generati dagli script in tools/ a partire dal modulo TTS)
scripts/data/db.gd        caricamento dei dati
scripts/core/             motore delle regole (nessuna dipendenza dall'interfaccia), effetti delle carte,
                          combattimento, siti, mana, speciali, IA (ai*.gd)
scripts/net/              Firebase (REST), partita online in lockstep, stanza d'attesa
scripts/ui/               menu, tavolo 3D, interfaccia di gioco, controller
tests/                    engine_test, qa_test (regole), exp_test (espansioni), sim (partite casuali,
                          SIM_SETS=base,ll,…), ai_sim (IA, AI_SETS=…), ui_play/qa_ui/exp_shot (interfaccia con
                          screenshot), online_play (online con Firebase finto)
tools/                    estrazione di dati e immagini dal modulo TTS, carte base in italiano
meshy/                    generazione delle miniature
docs/SPEC.md              specifica tecnica
```

## Scelte da verificare
- Tessere Campagna: una nuova tessera deve toccarne almeno 2 già piazzate, oppure toccarne una che a sua
  volta ne tocca almeno 2 (confermato).
- Solitario/cooperativo: +1 per carta rimasta nel mazzo del Neutrale e +5 se il round non è stato
  annunciato solo in caso di vittoria (confermato).
- Sotterraneo: con il dado oro/nero si prende un incantesimo, altrimenti un artefatto (dalla carta del sito).
- Non ancora presenti: combattimento tra giocatori, assalto cooperativo a una città, pesca delle tessere
  dalla scatola a mazzo esaurito, saccheggio fuori dal proprio turno.
- Nomi italiani dei nemici: traduzioni (i segnalini non hanno testo).
- Espansioni (da confermare col regolamento): Elusivo usa l'armatura bassa solo nella fase di Attacco se tutti
  gli attacchi del nemico sono stati bloccati (o ridotti a 0); Difensore aggiunge il bonus a un bersaglio non
  ancora difeso (anche a se stesso), una volta per combattimento, e in un attacco di gruppo valgono i bonus più
  alti; Vampirico +1 Armatura per ogni Ferita in mano o Unità ferita (non per le ferite del veleno negli
  scarti); Ululato del Lupo: +4 alla carta di lato solo per Movimento/Attacco/Blocco; Soppressione del Mana: il
  mana in più si prende da un gettone o cristallo dello stesso colore, se non c'è non si paga; Sentieri Druidici
  (base) riducono il primo spazio in cui la riduzione conta; Forziere Misterioso: gli stendardi rivelati non si
  possono assegnare (il Forziere torna in mano); Famigli Magici: il mantenimento si chiede a inizio round e
  senza cristalli se ne vanno; non si reclutano nelle Radure.
