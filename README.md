# Mage Knight — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Mage Knight** (Vlaada Chvátil, WizKids), Ultimate Edition,
gioco base. Componenti, illustrazioni e regole © dei rispettivi autori: le immagini vengono dal modulo
Tabletop Simulator «Mage Knight Plus (Highly Scripted)» e non vanno distribuite pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/Mage-Knight/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**.

## Cosa c'è
- **Scenari**: *Prima Ricognizione* (introduttivo), *Conquista in solitario* (con il giocatore Neutrale),
  *Cooperazione Totale* (2–3 eroi contro le città), *Conquista completa* (competitiva, 2–4 eroi,
  città di livello 4) e le varianti Blitz.
- **Eroi**: Arythea, Goldyx, Norowas, Tovak. Ogni posto può essere **Umano** o **IA** (Facile, Normale,
  Difficile); più umani sullo stesso dispositivo giocano a turno con la schermata *Passa il dispositivo*.
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
- **Combattimento tra giocatori** (Conquista Totale; nel menu *Combattimento tra giocatori: Sì/No*): chi
  entra nello spazio di un altro eroe può attaccarlo (fermarsi lì è già un attacco). Il difensore sceglie se
  affrontarlo *completamente* (gioca subito il suo turno successivo, con dado e abilità, poi lo salta) o
  *parzialmente*; poi ci si alternano attacchi a distanza/d'assedio e corpo a corpo, bloccando a turno; con
  i danni si feriscono eroe e unità, si rubano Artefatti o si costringe l'avversario a ritirarsi (Fama a chi
  vince se ha livello o Fama inferiori). Il pannello funziona per entrambi: in hotseat compare *Passa il
  dispositivo*, online agisce il posto del difensore. L'IA attacca quando la sua mano è nettamente superiore.
- **Assalto cooperativo alla città** (Cooperazione Totale): accanto a una città si invitano gli alleati
  adiacenti e si propone quanti difensori affronterà ciascuno; se tutti accettano, i difensori vengono
  distribuiti a caso, ognuno combatte i suoi, la città cade se sono tutti sconfitti (capo = più Scudi) e
  gli invitati saltano il turno successivo. Gli alleati IA propongono, accettano e si avvicinano alle città
  dove un compagno aspetta.
- **Salvataggio automatico**: dal menu, *Continua partita*.

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
tests/                    engine_test, qa_test (regole), pvp_test (giocatore contro giocatore e assalto
                          cooperativo), sim (partite casuali), ai_sim (IA), ui_play/qa_ui/pvp_ui (interfaccia
                          con screenshot), online_play (online con Firebase finto)
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
- Combattimento tra giocatori: consentito di default in Conquista Totale/Blitz, mai in Prima Ricognizione
  e nei cooperativi; nessun divieto nel primo round (il regolamento non lo prevede). Gli effetti speciali
  che colpiscono i nemici (distruggere, ridurre l'Armatura, impedire l'attacco…) non si possono usare contro
  le unità dell'avversario, e il difensore non può usare effetti "prima del turno" (es. saccheggio).
  Con il danno di un attacco a distanza non si ruba e non si costringe alla ritirata (solo corpo a corpo).
  L'aggressore che pareggia torna nello spazio da cui è entrato; se non è sicuro, Ritirata Forzata.
- Assalto cooperativo: l'ingresso in città dei partecipanti non costa Movimento; non si possono sfidare
  altri nemici scatenati adiacenti oltre a quelli provocati; servono almeno 2 difensori; al massimo 3
  proposte per turno; non disponibile negli scenari competitivi (le regole lo permettono "se d'accordo").
- I gettoni Ordine di Round a faccia in giù restano tali anche a cavallo della fine del round (il turno
  saltato può essere il primo del round successivo).
- Non ancora presenti: pesca delle tessere dalla scatola a mazzo esaurito, saccheggio fuori dal proprio turno.
- Nomi italiani dei nemici: traduzioni (i segnalini non hanno testo).
