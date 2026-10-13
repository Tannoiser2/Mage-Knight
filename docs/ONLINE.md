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
