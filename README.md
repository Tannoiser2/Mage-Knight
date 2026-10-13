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
- **Scenari** (tutti quelli del *Manuale degli Scenari* del gioco base, regolamento italiano pp. 18–22; nella
  schermata *Nuova partita* sono raggruppati, con numero di eroi, durata, descrizione e regole complete):
  - *Introduttivi*: **La Prima Ricognizione** (p. 18; 2–4 eroi, variante in solitario).
  - *Competitivi*: **Conquista Totale** e **Conquista Blitz** (p. 19), **Liberazione delle Miniere** (pp. 20–21:
    miniere sorvegliate da liberare, 4/7 Fama per miniera, Più Grande Liberatore), **Le Notti del Druido** (p. 21:
    Scudi sulle radure e incantesimo notturno che evoca mostri a Fama doppia), **I Signori del Sotterraneo** (p. 21:
    entrate segrete accanto a villaggi e monasteri, sotterranei e tombe da 4 punti, gallerie), **Conquista e
    Mantieni** (p. 22: mappa predefinita, castelli e torri da 3/2 punti Vittoria, a 4 in due squadre) e **Solo Uno
    Tornerà** (p. 22: il portale si chiude dopo il primo Giorno, vince chi vi si trova alla fine). Miniere, Druido e
    Sotterraneo si giocano anche **in solitario** (p. 20, «Altre missioni in solitario»).
  - *Cooperativi*: **Cooperazione Totale** e **Cooperazione Blitz** (p. 20; 2–3 eroi, 4 come variante della Nota 3
    a p. 15: il Neutrale usa il mazzo di un altro eroe; a 4 non si tolgono tattiche se non ne restano
    abbastanza per tutti).
  - *Solitario*: **Conquista in Solitario** (pp. 19–20) e **Conquista Blitz in Solitario** (preparazione del modulo
    TTS: 4 round, una città di livello 6).
  - Non disponibili: gli scenari di **Volkare** (*Volkare's Return*, *Volkare's Quest* e le varianti Blitz,
    La Legione Perduta: serve tutto il sistema di Volkare – esercito, movimento, assalti alla città – non
    implementato), gli scenari delle fazioni di **Shades of Tezla** (*Life and Death*, *The Realm of the Dead*, *The Hidden
    Valley*, *The Lost Relic*: capi fazione, cimiteri, ricompense di fazione), quelli di **Apocalypse
    Dragon** e quelli dei fan presenti nel modulo TTS. Le varianti opzionali del manuale (Megalopoli, Furioso!,
    asta degli eroi…) non sono selezionabili.
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
  base, in piedi al centro del loro segnalino che fa da basetta; più le strutture dei siti, ricavate dal
  disegno delle tessere e posate al centro dell'esagono: villaggio, monastero, castello, torre della magia,
  sotterraneo, tomba, antiche rovine, campo profughi, dedalo, labirinto, piramide, ziggurat). Le miniature
  non girano con la telecamera; i valori del nemico sono anche nel suggerimento dell'esagono. Si possono
  spegnere dal menu di gioco (*Miniature 3D: Sì/No*).
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
tests/                    engine_test, qa_test (regole), pvp_test (giocatore contro giocatore e assalto
                          cooperativo), exp_test (espansioni), scn_test (scenari: regole e partite IA),
                          sim (partite casuali, SIM_SETS=base,ll,…), menu_shot (schermata Nuova partita),
                          ai_sim (IA, AI_SETS=…), ui_play/qa_ui/pvp_ui/exp_shot (interfaccia con screenshot),
                          online_play (online con Firebase finto)
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
- Scenari (scelte dove il manuale è vago): Liberazione delle Miniere — in parità per il Più Grande Liberatore +2 a
  testa (come per le città); il dono dei minatori all'inizio di ogni Giorno/Notte non vale per il primo round.
  Notti del Druido — la radura si attiva terminando il turno su di essa; l'incantesimo richiede almeno una radura
  segnata ed è vietato in villaggi, monasteri, castelli, torri, città e campi; i mostri evocati non sconfitti
  scompaiono. Signori del Sotterraneo — entrate segrete solo su spazi senza sito né nemici, non palude/lago/
  montagna; se c'è un solo spazio valido (o in preparazione) la scelta è automatica; le gallerie non provocano i
  nemici scatenati; l'IA non le usa. Conquista e Mantieni — le Campagna coperte sono nelle due posizioni più vicine
  (4,-5 e 5,-1 dell'immagine), le Principali nelle altre quattro; la Fama dei difensori è dimezzata nemico per
  nemico; con 4 giocatori le squadre sono Posti 1+2 e 3+4; sono escluse tutte le Unità di livello IV. Solo Uno
  Tornerà — l'eroe eliminato esce dalla mappa; se tutti sono eliminati la partita finisce senza vincitori.
- Espansioni (da confermare col regolamento): Elusivo usa l'armatura bassa solo nella fase di Attacco se tutti
  gli attacchi del nemico sono stati bloccati (o ridotti a 0); Difensore aggiunge il bonus a un bersaglio non
  ancora difeso (anche a se stesso), una volta per combattimento, e in un attacco di gruppo valgono i bonus più
  alti; Vampirico +1 Armatura per ogni Ferita in mano o Unità ferita (non per le ferite del veleno negli
  scarti); Ululato del Lupo: +4 alla carta di lato solo per Movimento/Attacco/Blocco; Soppressione del Mana: il
  mana in più si prende da un gettone o cristallo dello stesso colore, se non c'è non si paga; Sentieri Druidici
  (base) riducono il primo spazio in cui la riduzione conta; Forziere Misterioso: gli stendardi rivelati non si
  possono assegnare (il Forziere torna in mano); Famigli Magici: il mantenimento si chiede a inizio round e
  senza cristalli se ne vanno; non si reclutano nelle Radure.
