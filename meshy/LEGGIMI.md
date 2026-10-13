# Miniature 3D con Meshy

Nel gioco da tavolo i nemici sono segnalini piatti. Per una mappa 3D più ricca si possono generare con
[Meshy](https://www.meshy.ai) delle miniature: **una per tipo di nemico del gioco base (29)** e
**4 strutture dei siti** (villaggio, monastero, fortezza, torre magica). Sono facoltative: se il file
`assets/miniatures/<id>.glb` c'è, il gioco lo usa; se non c'è, resta il segnalino.

## Cosa è già pronto
- `riferimenti/<id>.png` — immagini di riferimento dei nemici: l'illustrazione del segnalino (originale
  1024 px del modulo TTS) senza l'anello, con le icone dei valori cancellate e il soggetto scontornato
  su fondo trasparente. Prodotte da `prepara_riferimenti.py` (si può rilanciare: serve `pip install
  "rembg[cpu]" opencv-python-headless`).
  `riferimenti/site_<sito>.png` — l'esagono del sito ritagliato dalla tessera, solo come promemoria visivo.
- `genera_miniature.py` — manda le richieste a Meshy e salva i `.glb` in `assets/miniatures/`.
  - nemici: **immagine → 3D** dal riferimento; per 10 nemici con il segnalino troppo affollato
    o sfumato (Maghi di Altem, Balestrieri, Congelatori, Illusionisti, Monaci, Artiglieri, Maghi del Fuoco,
    Drago di Fuoco, Drago di Palude, Verme delle Cripte) **testo → 3D** con una descrizione
    (elenco `DA_TESTO` e descrizioni `PROMPT_NEMICI` in cima allo script);
  - siti: **testo → 3D** con i prompt `SITI`;
  - modelli leggeri per il web (≈8000 triangoli i nemici, 10000 i siti), salta quelli già fatti.

**Prima di spendere crediti guarda i riferimenti** (cartella `riferimenti/`): alcuni segnalini sono
scene con più figure e lo scontorno automatico non è perfetto. Per uno venuto male: rigeneralo da testo
(`--da-testo <id>`), oppure sostituisci a mano il PNG (soggetto intero, fondo trasparente o uniforme).

## Al mattino: come generarle
Con la chiave API (Meshy → Settings → API):
```
export MESHY_API_KEY=msy_...
python3 meshy/genera_miniature.py --elenco      # cosa c'è e cosa manca
python3 meshy/genera_miniature.py --prova       # controllo senza spendere
python3 meshy/genera_miniature.py high_dragon   # prova su un modello solo, poi guardalo
python3 meshy/genera_miniature.py               # tutte quelle che mancano (33)
```
Senza chiave, con la riga di comando di Meshy (accesso dal browser, una volta):
```
npx --yes --package=meshy-cli@0.4.0 -- meshy auth login --device
python3 meshy/genera_miniature.py nemici
```
In alternativa chiedi a Claude (con il plugin Meshy) di eseguire lo script o di generare i modelli
con le stesse impostazioni. Altre opzioni: `nemici`, `siti`, `--rifai <id>`, `--da-testo <id>`,
`--da-immagine <id>`, `--siti-da-immagine`.

Costo indicativo: un credito Meshy per ogni compito, testo → 3D ne usa due (anteprima + texture);
controlla il saldo prima di lanciare tutto.

## Compressione (automatica)
I `.glb` scaricati da Meshy pesano 15–180 MB: texture 2k/4k (colore, normal map, metallic/roughness) e,
per i modelli **testo → 3D**, da 0,5 a 5 milioni di triangoli (il limite di poligoni vale solo per
immagine → 3D). Per questo `genera_miniature.py`, subito dopo lo scaricamento, li comprime con
[glTF Transform](https://gltf-transform.dev) (via `npx`, serve Node.js; nessun credito Meshy):
1. se i triangoli sono più del doppio del previsto: `weld` + `simplify` (si arriva a ~18 000 triangoli
   per i nemici e 20–40 000 per i siti: le cuciture delle UV impediscono di scendere oltre senza
   rovinare la texture);
2. `resize` delle texture a 1024 px; poi normal map e metallic/roughness a 512 px (con Pillow);
3. l'originale resta in `meshy/originali/` (escluso da git), se un giorno servisse rifarla meglio.

Risultato: 0,5–1,4 MB per modello (villaggio 2,2 MB), 25 MB in tutto per 33 miniature.
Per comprimere a mano i `.glb` già presenti (gratis, non chiama Meshy):
```
python3 meshy/genera_miniature.py --comprimi              # tutti quelli > 3 MB (+ mappe a 512 px)
python3 meshy/genera_miniature.py --comprimi --rifai medusa   # forza anche uno già leggero
```
Equivalente a mano: `npx --yes @gltf-transform/cli@4.1.1 resize in.glb out.glb --width 1024 --height 1024`
(preceduto da `weld` e `simplify --ratio 0.01 --error 0.02` se i triangoli sono troppi).

**Dopo il primo import in Godot** rilancia `--comprimi`: imposta i file `.import` di
`assets/miniatures/` (texture estratte in WebP con perdita invece che senza perdita, niente LOD né mesh
d'ombra per i `.glb`) e poi riapri Godot o esegui `godot --headless --path . --import`. Senza questo
passo il `.pck` per il web cresce di parecchie decine di MB (texture salvate senza perdita).

## Come le usa il gioco
`scripts/ui/miniatures.gd` (`MKMiniatures`): `MKMiniatures.load_for(id)` restituisce la miniatura
normalizzata (altezza fissa, appoggiata al piano, centrata, rivolta verso chi guarda) oppure `null`.
Id: il tipo di nemico (`high_dragon`, `minotaur`…) e `site_keep`, `site_mage_tower`,
`site_monastery`, `site_village`. I nemici coperti non mostrano mai la miniatura (non si rivela chi
sono). Dopo aver aggiunto i `.glb` riapri il progetto in Godot (o rifai la build: la action di GitHub
li importa da sola). Tieni d'occhio il peso (vedi «Compressione»).

Sul tavolo (`scripts/ui/table3d.gd`): la miniatura del nemico sta in piedi **subito dietro il suo
segnalino** rispetto alla telecamera (così i valori stampati restano leggibili) e gira con la
telecamera; quelle dei siti (villaggio, monastero, fortezza, torre magica) stanno sul lato destro
dell'esagono, sempre visibili (il monastero bruciato sparisce). Nel menu di gioco c'è
**Miniature 3D: Sì/No** (si ricorda in `user://mk_settings.cfg`). Verifica visiva:
`tests/mini_shot.gd` (tutti i tipi di nemico scoperti, i siti, notte, telecamera ruotata, menu).
