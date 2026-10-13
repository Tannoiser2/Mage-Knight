#!/usr/bin/env python3
"""Genera i dati statici del "mondo" di Mage Knight e i relativi asset dal modulo TTS.

Uscite (relative alla radice del repo):
  data/tiles.json enemies.json ruins.json cities.json tactics.json rules.json scenarios.json
       heroes.json assets.json specials_world.json
  assets/tiles/  assets/enemies/  assets/ruins/  assets/models/  assets/tokens/
  assets/cards/tactic_*.webp  assets/cards/city_*.webp

Sorgenti: /home/claude/work/global.lua (tabelle Lua), /home/claude/work/objs.json (manifesto oggetti),
/home/claude/work/card_index.json, immagini e modelli in /mnt/user-data/uploads/Mage Knight/Mods.
I dati che il Lua non contiene (testi delle tattiche, valori "Elusivo", livelli delle città, scenari,
regole) sono trascritti a mano qui sotto dalle immagini del modulo e dal regolamento italiano.

Uso:  python3 tools/build_world.py [--no-images]
"""
import glob, json, math, os, re, sys
from PIL import Image, ImageDraw, ImageFont

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = '/home/claude/work'
MODS = '/mnt/user-data/uploads/Mage Knight/Mods'
IMG_DIR = MODS + '/Images/'
MDL_DIR = MODS + '/Models/'
NO_IMAGES = '--no-images' in sys.argv
ASSETS = {}          # manifesto id logico -> percorso relativo


def out(rel):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def write_json(rel, obj):
    with open(out(rel), 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
        f.write('\n')


def cache_file(url, folder=IMG_DIR):
    if not url:
        return None
    k = re.sub(r'[^A-Za-z0-9]', '', url)
    g = glob.glob(folder + k + '.*')
    return g[0] if g else None


def save_webp(im, rel, max_side=None, quality=85, asset_id=None):
    if asset_id:
        ASSETS[asset_id] = rel
    if NO_IMAGES:
        return rel
    if im.mode not in ('RGB', 'RGBA'):
        im = im.convert('RGBA' if 'A' in im.getbands() or im.mode == 'P' else 'RGB')
    if max_side and max(im.size) > max_side:
        s = max_side / max(im.size)
        im = im.resize((max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))), Image.LANCZOS)
    im.save(out(rel), 'WEBP', quality=quality, method=4)
    return rel


# ----------------------------------------------------------------------------------- Lua parser
class LuaParser:
    tok_re = re.compile(r'''\s*(?:(--\[\[.*?\]\])|(--[^\n]*)|("(?:\\.|[^"\\])*")|('(?:\\.|[^'\\])*')|'''
                        r'''(-?\d+\.?\d*(?:[eE][-+]?\d+)?)|([A-Za-z_][A-Za-z0-9_\.]*)|(.))''', re.S)

    def __init__(self, text, env):
        self.toks = []
        for m in self.tok_re.finditer(text):
            if m.group(1) or m.group(2):
                continue
            if m.group(3) is not None:
                self.toks.append(('s', m.group(3)[1:-1]))
            elif m.group(4) is not None:
                self.toks.append(('s', m.group(4)[1:-1]))
            elif m.group(5) is not None:
                v = m.group(5)
                self.toks.append(('n', float(v) if ('.' in v or 'e' in v.lower()) else int(v)))
            elif m.group(6) is not None:
                self.toks.append(('id', m.group(6)))
            elif m.group(7) is not None and m.group(7).strip():
                self.toks.append(('p', m.group(7)))
        self.i = 0
        self.env = env

    def peek(self, k=0):
        return self.toks[self.i + k] if self.i + k < len(self.toks) else (None, None)

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def value(self):
        t = self.next()
        if t[0] in ('s', 'n'):
            return t[1]
        if t == ('p', '{'):
            return self.table()
        if t == ('p', '-'):
            return -self.value()
        if t[0] == 'id':
            if t[1] in ('true', 'false', 'nil'):
                return {'true': True, 'false': False, 'nil': None}[t[1]]
            cur = self.env
            for part in t[1].split('.'):
                if isinstance(cur, dict) and part in cur:
                    cur = cur[part]
                else:
                    return '<' + t[1] + '>'
            return cur
        raise ValueError(t)

    def table(self):
        arr, d = [], {}
        while True:
            t = self.peek()
            if t == ('p', '}'):
                self.next()
                break
            if t == ('p', '['):
                self.next()
                k = self.value()
                assert self.next() == ('p', ']')
                assert self.next() == ('p', '=')
                d[k] = self.value()
            elif t[0] == 'id' and self.peek(1) == ('p', '='):
                self.next(); self.next()
                d[t[1]] = self.value()
            else:
                arr.append(self.value())
            if self.peek() in (('p', ','), ('p', ';')):
                self.next()
        if d and arr:
            for i, v in enumerate(arr):
                d[i + 1] = v
            return d
        return d if d else arr


def lua_table(src, name, env):
    m = re.search(r'^' + re.escape(name) + r'\s*=\s*\{', src, re.M)
    p = LuaParser(src[m.end() - 1:], env)
    p.next()
    return p.table()


def lang(s, want='it'):
    if not isinstance(s, str) or '{' not in s:
        return s
    parts = dict(re.findall(r'\{([a-z\-]+)\}([^{]*)', s))
    return (parts.get(want) or parts.get('en') or s).strip()


SRC = open(WORK + '/global.lua', encoding='utf-8').read()
ENV = {}
for _n in ['startTerrain', 'cityModel', 'elementalist', 'darkCrusader', 'volkare', 'portal']:
    ENV[_n] = lua_table(SRC, _n, ENV)
ENV['GUID'] = lua_table(SRC, 'GUID', ENV)
ENV['monsterPiles'] = lua_table(SRC, 'monsterPiles', ENV)
TERRAIN = lua_table(SRC, 'terrainTiles', ENV)
PUGS = lua_table(SRC, 'monsterPugs', ENV)
KNIGHTS = lua_table(SRC, 'mageKnights', ENV)
REPUTATION = lua_table(SRC, 'reputationTable', ENV)
ROSTER = lua_table(SRC, 'setupContentRoster', ENV)
TACTIC_GUIDS = lua_table(SRC, 'tacticCard', ENV)
CITY_ZONES = lua_table(SRC, 'cityScriptZones', ENV)
OBJS = json.load(open(WORK + '/objs.json', encoding='utf-8'))
BY_GUID = {}
for _o in OBJS:
    BY_GUID.setdefault(_o['guid'], _o)
CARDS = {c['guid']: c for c in json.load(open(WORK + '/card_index.json', encoding='utf-8'))}

SITE_SHEET = IMG_DIR + 'httpssteamusercontentaakamaihdnetugc1477793018962985641585012594962974A020D37C4DD880D9C7F3AA62C2.jpg'
_site_sheet_img = None


def site_card(idx):
    """Carte descrizione sito (foglio 4x7, italiano)."""
    global _site_sheet_img
    if _site_sheet_img is None:
        _site_sheet_img = Image.open(SITE_SHEET).convert('RGB')
    W, H = _site_sheet_img.size
    cw, ch = W // 4, H // 7
    return _site_sheet_img.crop(((idx % 4) * cw, (idx // 4) * ch, (idx % 4 + 1) * cw, (idx // 4 + 1) * ch))


# =================================================================================== TILES
SITE_MAP = {'': '', 'portal': 'portal', 'glade': 'glade', 'village': 'village', 'rampaging': 'orcs',
            'mine': 'mine', 'keep': 'keep', 'mage tower': 'mage_tower', 'monastery': 'monastery',
            'monster den': 'monster_den', 'dungeon': 'dungeon', 'ruin': 'ruins', 'camp': 'camp',
            'maze': 'maze', 'oasis': 'oasis', 'ziggurat': 'ziggurat', 'spawning grounds': 'spawning_grounds',
            'tomb': 'tomb', 'draconum': 'draconum', 'labyrinth': 'labyrinth', 'pyramid': 'pyramid',
            "Volkare's Camp": 'volkare_camp'}
DIRS = ['center', '0', '60', '120', '180', '240', '300']
TILE_PX = {'w': 2048, 'h': 1970, 'center': [1024.0, 985.0], 'hex_radius': 394.0}


def tile_set(guid, kind, number):
    ll = ROSTER['lostLegion']['terrain']
    ap = ROSTER['apocalypse']['terrain']
    if guid in ll['country'] or guid in ll['core'] or number == 99:
        return 'll'
    if guid in ap['country'] or guid in ap['core']:
        return 'apocalypse'
    return 'base'


def build_tiles():
    tiles = {}
    G = ENV['GUID']['tile']
    for guid, t in TERRAIN.items():
        if not isinstance(t, dict) or 'hexType' not in t or t.get('tileType') not in ('starting', 'country', 'core'):
            continue
        num = t['tileNumber']
        city = None
        if guid == ENV['startTerrain']['wedge']:
            tid, kind = 'start_a', 'start'
        elif guid == ENV['startTerrain']['open']:
            tid, kind = 'start_b', 'start'
        elif t['tileType'] == 'country':
            tid, kind = 'c%02d' % num, 'country'
        elif num == 99:
            tid, kind = 'volkare_camp', 'core'
        else:
            tid, kind = 'k%02d' % num, 'core'
        hexes, mines = {}, {}
        for d in DIRS:
            feat = t['hexFeature'][d]
            site = feat
            if feat.startswith('city '):
                city = feat.split()[1]
                site = 'city'
                kind = 'city'
            else:
                site = SITE_MAP[feat]
            hexes[d] = {'t': t['hexType'][d], 'site': site}
        for d, cols in (t.get('mineColors') or {}).items():
            cols = [c.lower() for c in cols]
            mines[d] = cols[0] if len(cols) == 1 else cols
            hexes[d]['mine'] = mines[d]
        rec = {'kind': kind, 'number': num, 'set': tile_set(guid, kind, num), 'guid': guid,
               'img': 'assets/tiles/%s.webp' % tid, 'hexes': hexes, 'mines': mines}
        if city:
            rec['city'] = city
        if t.get('wallList'):
            rec['walls'] = {k: sorted(v.keys(), key=lambda s: DIRS.index(s)) for k, v in t['wallList'].items()}
        o = BY_GUID[guid]
        src = cache_file(o.get('diffuse'))
        if not src:
            print('!! texture mancante per', tid)
        else:
            im = Image.open(src)
            rec['img_size'] = list(im.size)
            if im.size != (TILE_PX['w'], TILE_PX['h']):
                print('!! dimensione inattesa', tid, im.size)
            save_webp(im.convert('RGB'), rec['img'], max_side=2048, asset_id='tile_' + tid)
        tiles[tid] = rec
    order = sorted(tiles, key=lambda k: ({'s': 0, 'c': 1, 'k': 2, 'v': 3}[k[0]], k))
    tiles = {k: tiles[k] for k in order}
    doc = {
        '_notes': {
            'dirs': 'Chiavi degli esagoni: center=(0,0), "0"=W(-1,0), "60"=SW(-1,+1), "120"=SE(0,+1), '
                    '"180"=E(+1,0), "240"=NE(+1,-1), "300"=NW(0,-1) (assiali, punta in alto). Verificato su '
                    'tessere A, 2 e 12.',
            'texture': 'Tutte le texture sono %dx%d px; centro dell\'esagono centrale = %s px, raggio esagono '
                       '(centro-vertice) = %.0f px; vicini a ±√3·r in x e ±1.5·r in y. Le texture sono copiate '
                       'senza ridimensionare.' % (TILE_PX['w'], TILE_PX['h'], TILE_PX['center'], TILE_PX['hex_radius']),
            'texture_px': TILE_PX,
            'sites': 'orcs = Orchi Predoni (nemico verde infuriato), draconum = Draconum (nemico rosso '
                     'infuriato), ruins = Antiche Rovine (segnalino giallo), keep = Castello, mage_tower = Torre '
                     'della Magia, dungeon = Sotterraneo, tomb = Tomba, monster_den = Tana del Mostro, '
                     'spawning_grounds = Terreni di Nidificazione, glade = Radura Magica, mine = Miniera di '
                     'Cristallo (colore in "mine"), camp = Campo Profughi (LL), maze/labyrinth = Dedalo/Labirinto '
                     '(LL), oasis/pyramid/ziggurat (Apocalypse Dragon).',
            'mines': 'mines: {dir: colore} (stringa); nelle tessere di espansione una miniera può produrre più '
                     'colori a scelta (Miniere Profonde) e allora il valore è un array.',
            'walls': 'walls (solo espansioni): per ogni esagono, l\'elenco dei lati (direzioni) con un muro.',
            'sets': 'base = gioco base (Campagna 1-11, Centrali 1-4, Città 5-8, iniziali A/B); '
                    'll = Lost Legion (Campagna 12-14, Centrali 9-10, campo di Volkare); apocalypse = '
                    'Apocalypse Dragon (Campagna 15-17, Centrali 11-12). Fonte: setupContentRoster del Lua.',
            'kinds': 'start | country | core | city (k05..k08 sono le tessere città: verde, blu, bianca, rossa).',
            'terrain': 'plains pianura, hills colline, forest foresta, wasteland terre perdute (landa), desert '
                       'deserto, swamp palude, lake lago, mountain montagna, ocean oceano.',
        },
        'tiles': tiles,
    }
    write_json('data/tiles.json', doc)
    return tiles


# =================================================================================== ENEMIES
COLOR_MAP = {'green': 'green', 'gray': 'gray', 'tan': 'brown', 'purple': 'violet', 'red': 'red', 'white': 'white'}
ELEM = {'P': 'phys', 'F': 'fire', 'I': 'ice', 'IF': 'cold'}
# Valore di armatura "Elusivo" letto sulle immagini dei segnalini (il Lua ha solo elusive=true).
ELUSIVE_ARMOR = {'cloud_griffons': 8, 'crystal_sprites': 2, 'orc_tracker': 6, 'vampiric_dragon': 16,
                 'lightning_dragon': 14, 'storm_dragon': 14, 'pain_wraith': 8, 'vampire': 10,
                 'air_elemental': 8, 'shadow': 8, 'shocktroops': 6}
NAMES_IT = {
    'diggers': 'Scavatori', 'cursed_hags': 'Megere Maledette', 'ironclads': 'Corazzati', 'prowlers': 'Predatori',
    'wolf_riders': 'Cavalca Lupi', 'orc_summoners': 'Orchi Evocatori', 'orc_tracker': 'Orco Segugio',
    'orc_skirmishers': 'Orchi Schermagliatori', 'orc_stonethrower': 'Orco Lanciapietre',
    'orc_war_beasts': 'Bestie da Guerra degli Orchi', 'elemental_priestesses': 'Sacerdotesse Elementali',
    'cloud_griffons': 'Grifoni delle Nubi', 'elven_protectors': 'Protettori Elfici',
    'centaur_outriders': 'Centauri Esploratori', 'crystal_sprites': 'Folletti di Cristallo',
    'corrupted_priests': 'Sacerdoti Corrotti', 'shrouded_necromancers': 'Negromanti Incappucciati',
    'gibbering_ghouls': 'Ghoul Farfuglianti', 'zombie_horde': 'Orda di Zombi',
    'skeletal_warriors': 'Guerrieri Scheletro',
    'swordsmen': 'Spadaccini', 'golems': 'Golem', 'crossbowmen': 'Balestrieri', 'guardsmen': 'Guardie',
    'heroes_1': 'Eroi', 'heroes_2': 'Eroi', 'heroes_3': 'Eroi', 'heroes_4': 'Eroi', 'thugs': 'Teppisti',
    'shocktroops': "Truppe d'Assalto",
    'gargoyle': 'Gargoyle', 'crypt_worm': 'Verme delle Cripte', 'werewolf': 'Lupo Mannaro',
    'minotaur': 'Minotauro', 'medusa': 'Medusa', 'hydra': 'Idra', 'manticore': 'Manticora', 'shadow': 'Ombra',
    'blood_demon': 'Demone di Sangue', 'pain_wraith': 'Spettro del Dolore', 'vampire': 'Vampiro',
    'mummy': 'Mummia', 'air_elemental': "Elementale dell'Aria", 'fire_elemental': 'Elementale del Fuoco',
    'water_elemental': "Elementale dell'Acqua", 'earth_elemental': 'Elementale della Terra',
    'ice_golems': 'Golem di Ghiaccio', 'fire_golems': 'Golem di Fuoco', 'monks': 'Monaci',
    'ice_mages': 'Maghi del Ghiaccio', 'illusionists': 'Illusionisti', 'fire_mages': 'Maghi del Fuoco',
    'magic_familiars': 'Famigli Magici', 'sorcerers': 'Stregoni',
    'swamp_dragon': 'Drago di Palude', 'high_dragon': 'Drago Supremo', 'ice_dragon': 'Drago di Ghiaccio',
    'fire_dragon': 'Drago di Fuoco', 'dragon_summoner': 'Evocatore di Draghi', 'storm_dragon': 'Drago della Tempesta',
    'lava_dragon': 'Drago di Lava', 'vampiric_dragon': 'Drago Vampiro', 'death_dragon': 'Drago della Morte',
    'savage_dragon': 'Drago Selvaggio', 'lightning_dragon': 'Drago del Fulmine',
    'altem_guardsmen': 'Guardie di Altem', 'altem_mages': 'Maghi di Altem', 'freezers': 'Congelatori',
    'gunners': 'Artiglieri', 'ice_catapult': 'Catapulta di Ghiaccio', 'fire_catapult': 'Catapulta di Fuoco',
    'delphana_masters': 'Maestri Delphana', 'grim_legionnaires': 'Legionari Torvi',
}
LUA_FLAG_DOC = {
    'name': 'nome inglese -> name_en / id', 'pugType': 'colore: green, gray, tan→brown, purple→violet, red, white; '
    'yellow = segnalini Rovine (in ruins.json); leader/possessed/dragonHead/horseman = espansioni (Tezla, '
    'Apocalypse Dragon) non esportate', 'fame': 'fame', 'armour': 'armor',
    'attack': 'attacks: {P|F|I|IF: [valori]} -> [{v, elem: phys|fire|ice|cold}] (ordine del Lua; più valori = '
    'attacchi multipli); M = attacco dei Posseduti (non esportato)',
    'monsters': 'evocatore: summon:<colore> per ogni voce (green, tan→brown); assenza di attack = 0 attacchi',
    'fortified': 'fortified', 'unfortified': 'unfortified (mai fortificato, anche nei siti)', 'swiftness': 'swift',
    'brutal': 'brutal', 'poison': 'poison', 'paralyse': 'paralyze', 'pResist': 'resist_phys',
    'fResist': 'resist_fire', 'iResist': 'resist_ice', 'elusive': 'elusive (+ campo elusive_armor letto sul '
    'segnalino)', 'cumbersome': 'cumbersome', 'arcaneImmunity': 'arcane_immunity', 'assassination': 'assassinate',
    'vampiric': 'vampiric', 'defend': 'defend:<n>', 'reputation': 'rep_on_defeat:<±n> (Eroi -1, Teppisti +1; '
    'il segnalino mostra il valore accanto alla Fama)', 'reward': 'reward=1 sui nemici di fazione di Shades of '
    'Tezla: faction_reward', 'faction': 'faction: Dark|Elem (Tezla)', 'boost': 'solo Posseduti (non esportato)',
    'original': 'immagine del fronte (usata)', 'alternate': 'immagine alternativa (non usata)',
    'required': 'solo Rovine (altare)'}


def enemy_set(guid):
    for grp in ROSTER['lostLegion']['enemies']:
        if guid in grp['tokens']:
            return 'll'
    for fac in ('dark', 'elementalist'):
        for grp in ROSTER['shadesOfTezla']['enemies'][fac]:
            if guid in grp['tokens']:
                return 'tezla'
    return 'base'


def snake(name):
    return re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')


def build_enemies():
    types = {}
    heroes_variants = []
    for guid, e in PUGS.items():
        if not isinstance(e, dict) or e.get('pugType') not in COLOR_MAP:
            continue
        name = e['name']
        tid = snake(name)
        if name == 'Heroes':
            key = json.dumps(e.get('attack'), sort_keys=True)
            if key not in heroes_variants:
                heroes_variants.append(key)
            tid = 'heroes_%d' % (heroes_variants.index(key) + 1)
        attacks = []
        for k, vals in (e.get('attack') or {}).items():
            for v in vals:
                attacks.append({'v': v, 'elem': ELEM[k]})
        ab = []
        flagmap = [('fortified', 'fortified'), ('unfortified', 'unfortified'), ('swiftness', 'swift'),
                   ('brutal', 'brutal'), ('poison', 'poison'), ('paralyse', 'paralyze'),
                   ('pResist', 'resist_phys'), ('fResist', 'resist_fire'), ('iResist', 'resist_ice'),
                   ('elusive', 'elusive'), ('cumbersome', 'cumbersome'), ('arcaneImmunity', 'arcane_immunity'),
                   ('assassination', 'assassinate'), ('vampiric', 'vampiric')]
        for flag, norm in flagmap:
            if e.get(flag):
                ab.append(norm)
        for m in e.get('monsters') or []:
            ab.append('summon:' + COLOR_MAP.get(m, m))
        if e.get('defend'):
            ab.append('defend:%d' % e['defend'])
        if e.get('reputation'):
            ab.append('rep_on_defeat:%+d' % e['reputation'])
        if e.get('reward'):
            ab.append('faction_reward')
        color = COLOR_MAP[e['pugType']]
        if tid in types:
            types[tid]['copies'] += 1
            types[tid]['guids'].append(guid)
            continue
        rec = {'id': tid, 'name_en': name, 'name_it': NAMES_IT.get(tid, name), 'color': color,
               'set': enemy_set(guid), 'armor': e.get('armour', 0), 'attacks': attacks, 'fame': e['fame'],
               'abilities': ab, 'copies': 1, 'img': 'assets/enemies/%s.webp' % tid, 'back': color,
               'guids': [guid]}
        if 'elusive' in ab:
            rec['elusive_armor'] = ELUSIVE_ARMOR[tid]
        if e.get('faction'):
            rec['faction'] = {'Dark': 'dark', 'Elem': 'elementalist'}[e['faction']]
        src = cache_file(e.get('original'))
        if src:
            save_webp(Image.open(src), rec['img'], max_side=256, asset_id='enemy_' + tid)
        else:
            print('!! immagine nemico mancante', tid)
        types[tid] = rec
    # retri per colore (dal primo segnalino di ogni sacchetto)
    backs = {}
    for tid, rec in types.items():
        c = rec['color']
        if c in backs:
            continue
        o = BY_GUID.get(rec['guids'][0])
        src = cache_file(o.get('img2')) if o else None
        if src:
            backs[c] = 'assets/enemies/back_%s.webp' % c
            save_webp(Image.open(src), backs[c], max_side=256, asset_id='enemy_back_' + c)
    order = ['green', 'gray', 'brown', 'violet', 'red', 'white']
    setorder = {'base': 0, 'll': 1, 'tezla': 2}
    types = dict(sorted(types.items(), key=lambda kv: (order.index(kv[1]['color']), setorder[kv[1]['set']])))
    counts = {}
    for r in types.values():
        if r['set'] == 'base':
            counts[r['color']] = counts.get(r['color'], 0) + r['copies']
    doc = {'_notes': {
        'lua_flags': LUA_FLAG_DOC,
        'abilities': 'fortified Fortificato, unfortified Mai fortificato, swift Rapido, brutal Brutale, poison '
                     'Velenoso, paralyze Paralizzante, resist_phys/resist_fire/resist_ice Resistenza, elusive '
                     'Elusivo (elusive_armor = armatura alta), cumbersome Ingombrante, arcane_immunity Immunità '
                     'arcana, assassinate Assassinio, vampiric Vampirico, defend:n Difensore, summon:<colore> '
                     'Evocatore (pesca un nemico di quel colore in fase di blocco), rep_on_defeat:±n Reputazione '
                     'alla sconfitta, faction_reward ricompensa di fazione (Tezla).',
        'colors': 'green=Orchi Predoni (verde), gray=Castelli (grigio), brown=Sotterranei/Tane (marrone), '
                  'violet=Torri della Magia (viola), red=Draconum (rosso), white=Città (bianco).',
        'names_it': 'I segnalini non riportano testo: i nomi italiani sono traduzioni (Cavalca Lupi e Minotauro '
                    'dalla Guida); da rivedere col traduttore.',
        'base_counts': counts,
        'heroes': 'Gli "Eroi" grigi (Lost Legion) hanno 4 segnalini con statistiche diverse: heroes_1..4.'},
        'enemies': types, 'backs': backs}
    write_json('data/enemies.json', doc)
    return types


# =================================================================================== RUINS
RUIN_REWARD = {'1 Artifact': ['artifact'], '2 Artifacts': ['artifact', 'artifact'],
               '1 Artifact and 1 Spell': ['artifact', 'spell'],
               '1 Spell and 1 Basic crystals of each colour': ['spell', 'crystals_all'],
               '1 Unit (Regular or Elite)': ['unit'], '1 Basic crystals of each colour': ['crystals_all'],
               '1 Spell and 1 Advanced Action': ['spell', 'aa'],
               '1 Artifact and 1 Advanced Action': ['artifact', 'aa']}
MANA_RGB = {'red': (200, 40, 30), 'blue': (40, 90, 210), 'green': (40, 160, 60), 'white': (235, 235, 235)}
FONT = os.path.join(ROOT, 'assets/fonts/BarlowCondensed-SemiBold.ttf')


def ruin_image(rec, enemy_backs):
    S = 256
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = S / 2 - 4
    pts = [(S / 2 + r * math.cos(math.radians(a)), S / 2 + r * math.sin(math.radians(a))) for a in range(30, 390, 60)]
    d.polygon(pts, fill=(226, 190, 40, 255), outline=(120, 90, 10, 255))
    d.polygon([(S / 2 + (r - 10) * math.cos(math.radians(a)), S / 2 + (r - 10) * math.sin(math.radians(a)))
               for a in range(30, 390, 60)], outline=(160, 120, 20, 255))
    try:
        f1 = ImageFont.truetype(FONT, 30)
        f2 = ImageFont.truetype(FONT, 24)
    except OSError:
        f1 = f2 = ImageFont.load_default()
    if rec['kind'] == 'altar':
        cols = rec['altar_cost']
        n = len(cols)
        for i, c in enumerate(cols):
            x = S / 2 + (i - (n - 1) / 2) * 46
            d.ellipse((x - 19, 78, x + 19, 116), fill=MANA_RGB[c] + (255,), outline=(40, 30, 10, 255), width=2)
        d.text((S / 2, 150), 'Altare', font=f1, fill=(60, 30, 0, 255), anchor='mm')
        d.text((S / 2, 182), '%d Fama' % rec['fame'], font=f1, fill=(60, 30, 0, 255), anchor='mm')
    else:
        n = len(rec['enemies'])
        for i, c in enumerate(rec['enemies']):
            x = S / 2 + (i - (n - 1) / 2) * 62
            b = enemy_backs.get(c)
            if b:
                tok = b.resize((56, 56)).convert('RGBA')
                mask = Image.new('L', (56, 56), 0)
                ImageDraw.Draw(mask).ellipse((0, 0, 55, 55), fill=255)
                im.paste(tok, (int(x - 28), 70), mask)
        lines, cur = [], ''
        for w in rec['reward_it'].split():
            t = (cur + ' ' + w).strip()
            if d.textlength(t, font=f2) > 170 and cur:
                lines.append(cur)
                cur = w
            else:
                cur = t
        lines.append(cur)
        for i, ln in enumerate(lines):
            d.text((S / 2, 150 + i * 26), ln, font=f2, fill=(60, 30, 0, 255), anchor='mm')
    return im


def build_ruins(enemies):
    backs = {}
    for c in COLOR_MAP.values():
        p = os.path.join(ROOT, 'assets/enemies/back_%s.webp' % c)
        if os.path.exists(p):
            backs[c] = Image.open(p).convert('RGB')
    ruins = {}
    n_alt = n_en = 0
    for guid, e in PUGS.items():
        if not isinstance(e, dict) or e.get('pugType') != 'yellow':
            continue
        rec = {'guid': guid, 'set': enemy_set(guid)}
        if e.get('required'):
            req = lang(e['required'], 'en')
            if 'Green, 1 Blue' in req:
                cols = ['green', 'blue', 'white', 'red']
                rid = 'altar_all'
            else:
                c = req.split()[1].lower()
                cols = [c] * 3
                rid = 'altar_' + c
            rec.update({'id': rid, 'kind': 'altar', 'altar_color': cols[0] if len(set(cols)) == 1 else 'all',
                        'altar_cost': cols, 'fame': e['fame'], 'rewards': [{'fame': e['fame']}],
                        'text_it': 'Altare: paga %s come tributo; contrassegna lo spazio con uno Scudo e ottieni %d '
                                   'Fama.' % (lang(e['required'], 'it'), e['fame'])})
            n_alt += 1
        else:
            cols = [COLOR_MAP[m] for m in e['monsters']]
            rew_en = lang(e['reward'], 'en')
            n_en += 1
            rid = 'enemies_' + '_'.join(cols)
            while rid in ruins:
                rid += 'b'
            rec.update({'id': rid, 'kind': 'enemies', 'enemies': cols, 'rewards': RUIN_REWARD[rew_en],
                        'reward_it': lang(e['reward'], 'it'),
                        'text_it': 'Nemici: %s. Se li sconfiggi tutti, contrassegna lo spazio con uno Scudo e '
                                   'ricevi: %s.' % (', '.join(cols), lang(e['reward'], 'it'))})
        rec['img'] = 'assets/ruins/%s.webp' % rec['id']
        ASSETS['ruin_' + rec['id']] = rec['img']
        if not NO_IMAGES:
            ruin_image(rec, backs).save(out(rec['img']), 'WEBP', quality=90)
        ruins[rec['id']] = rec
    doc = {'_notes': {
        'source': 'Tabella monsterPugs del Lua (pugType yellow). Le texture dei segnalini gialli NON sono nella '
                  'cache del modulo: le immagini in assets/ruins/ sono generate (esagono giallo + mana o retri '
                  'dei nemici + ricompensa).',
        'rules': 'Rivelato a faccia in su di Giorno, a faccia in giù di Notte (si scopre all\'inizio del '
                 'prossimo Giorno o quando qualcuno entra). Altare: paga 3 mana del colore -> Scudo + Fama. '
                 'Nemici: pesca i nemici indicati e combattili; quelli non sconfitti restano; sconfitto l\'ultimo -> '
                 'Scudo + ricompensa.',
        'rewards': 'artifact, spell, aa (Azione Avanzata dall\'offerta), unit (Unità a scelta dall\'offerta, '
                   'regolare o élite, gratis), crystals_all (1 cristallo per ciascun colore base), {fame:n}.',
        'counts': {'altars': n_alt, 'enemies': n_en}}, 'ruins': ruins}
    write_json('data/ruins.json', doc)
    return ruins


# =================================================================================== CITIES
CITY_CARD_IDX = {'green': 20, 'white': 21, 'red': 22, 'blue': 23}
CITY_GUID = {'green': '8de450', 'white': 'a37b57', 'red': 'bd6ab1', 'blue': '79a723'}
CITY_DATA = {
    'white': {'name_it': 'Città Bianca', 'name_en': 'White City',
              'assault': [['armor', 1]], 'assault_it': 'Tutti i difensori ottengono Armatura +1.',
              'services': [{'type': 'recruit_any'}, {'type': 'elite_to_offer', 'cost': 2}],
              'services_it': "Puoi reclutare Unità di ogni tipo. Puoi anche pagare 2 Influenza per aggiungere "
                             "un'Unità d'Élite (oro) all'offerta."},
    'green': {'name_it': 'Città Verde', 'name_en': 'Green City',
              'assault': [['grant_phys', 'poison']],
              'assault_it': 'Tutti i difensori con Attacco fisico ottengono Velenoso.',
              'services': [{'type': 'buy_aa', 'cost': 6, 'from': ['offer', 'deck_top'], 'to': 'deck_top'}],
              'services_it': "Puoi pagare 6 Influenza per una carta dall'offerta Azioni Avanzate oppure una "
                             "casuale dalla cima del loro mazzo. Mettila in cima al tuo mazzo Impresa."},
    'blue': {'name_it': 'Città Blu', 'name_en': 'Blue City',
             'assault': [['attack_elem', 'ice', 2], ['attack_elem', 'fire', 2], ['attack_elem', 'cold', 1]],
             'assault_it': 'I difensori ottengono Attacco +2 se di Ghiaccio o Fuoco e +1 se di Fuoco Freddo.',
             'services': [{'type': 'buy_spell', 'cost': 7, 'mana': 'spell_color'}],
             'services_it': 'Puoi comprare Incantesimi come in una Torre della Magia (7 Influenza + 1 mana del '
                            "colore dell'Incantesimo)."},
    'red': {'name_it': 'Città Rossa', 'name_en': 'Red City',
            'assault': [['grant_phys', 'brutal']],
            'assault_it': 'Tutti i difensori con Attacco fisico ottengono Brutale.',
            'services': [{'type': 'buy_artifact', 'cost': 12, 'when': 'end_of_turn_reward'}],
            'services_it': 'Puoi comprare Artefatti per 12 Influenza ciascuno. Pescali a fine turno come '
                           'ricompense di combattimento.'},
}


def classify_token(px):
    import statistics as st
    r = sum(p[0] for p in px) / len(px); g = sum(p[1] for p in px) / len(px); b = sum(p[2] for p in px) / len(px)
    sd = st.pstdev([sum(p) / 3 for p in px])
    if b > r + 5 and r < 150 and g < 125:
        return 'violet'
    if sd < 22:
        return None
    if r < 135 and abs(r - b) < 25:
        return 'gray'
    if r - b > 45:
        return 'brown'
    if sd > 40 and 150 < r < 195:
        return 'white'
    return None


def city_garrisons(card):
    """Legge i colori dei gettoni per i livelli 1-11 sulla carta città (1400x1000)."""
    im = card.convert('RGB')
    sx, sy = im.size[0] / 1400, im.size[1] / 1000
    levels = {}
    for lvl in range(1, 12):
        y = (102 + 80.2 * (lvl - 1)) * sy
        row = []
        for k in range(5):
            x = (850 + 92.5 * k) * sx
            px = [im.getpixel((int(x + dx * sx), int(y + dy * sy))) for dx in range(-26, 27, 2)
                  for dy in range(-26, 27, 2) if dx * dx + dy * dy <= 26 * 26]
            c = classify_token(px)
            if c is None:
                break
            row.append(c)
        levels[str(lvl)] = row
    return levels


def build_cities():
    cities = {}
    for color, idx in CITY_CARD_IDX.items():
        card = site_card(idx)
        gar = city_garrisons(card)
        rec = dict(CITY_DATA[color])
        rec.update({'color': color, 'garrison': gar, 'img': 'assets/cards/city_%s.webp' % color,
                    'card_guid': CITY_GUID[color],
                    'model': 'assets/models/city_%s.obj' % color,
                    'model_texture': 'assets/models/city_%s.webp' % color,
                    'text_it': CARDS[CITY_GUID[color]]['desc'],
                    'tile': {'green': 'k05', 'blue': 'k06', 'white': 'k07', 'red': 'k08'}[color]})
        save_webp(card, rec['img'], max_side=1000, asset_id='city_card_' + color)
        cities[color] = rec
    save_webp(site_card(25), 'assets/cards/city_site.webp', max_side=1000, asset_id='city_card_site')
    doc = {'_notes': {
        'garrison': 'garrison[livello] = colori dei segnalini nemico (letti automaticamente dalla carta città: '
                    'gray, brown, violet, white). Livelli 1-11. I gettoni si piazzano a faccia in giù e si rivelano '
                    'quando un giocatore è adiacente (anche di Notte).',
        'rules_it': "Città (sito fortificato). Non ancora conquistata: può essere assaltata da uno o più giocatori; "
                    "chi assalta subisce Reputazione -1. I difensori sono fortificati e ricevono i bonus della "
                    "carta Città. Ogni nemico sconfitto dà al giocatore uno Scudo sulla carta Città; sconfitti tutti, "
                    "la città è conquistata e il giocatore con più Scudi ne è il leader (parità: chi ha piazzato per "
                    "primo). Già conquistata: niente combattimento tra giocatori; si reclutano Unità con il simbolo "
                    "città; servizi del lato corto della carta; bonus Influenza = numero dei propri Scudi in città. "
                    "Bonus: chi termina il turno su o adiacente a una città conquistata ha limite di mano +2 se "
                    "leader, +1 se ha almeno uno Scudo lì.",
        'assault': 'Modificatori durante l\'assalto: ["armor", n] armatura +n a tutti; ["grant_phys", abilità] i '
                   'difensori con attacco fisico ottengono l\'abilità; ["attack_elem", elem, n] +n agli attacchi '
                   'di quell\'elemento.',
        'hand_bonus': {'leader': 2, 'shield': 1}, 'influence_per_shield': 1, 'assault_rep': -1},
        'cities': cities}
    write_json('data/cities.json', doc)
    return cities


# =================================================================================== TACTICS
TACTICS = [
    # id, day, n, name_it, name_en, text_it, effect
    ('early_bird', True, 1, 'Mattiniero', 'Early Bird', '', []),
    ('rethink', True, 2, 'Ripensamento', 'Rethink',
     'Quando prendi questa Tattica, scarta fino a 3 carte (incluse le Ferite) dalla tua mano, quindi pesca '
     'altrettante carte. Rimescola la tua pila degli scarti nel tuo mazzo Impresa.',
     ['special', 'tactic_rethink']),
    ('mana_steal', True, 3, 'Rubare Mana', 'Mana Steal',
     'Quando prendi questa Tattica, prendi un dado mana di un colore base dalla Riserva e mettilo su questa '
     'carta. Puoi utilizzare quel mana in un tuo turno qualsiasi di questo Giorno. Se lo fai, ritiralo alla fine '
     'di quel turno e rimettilo nella Riserva.', ['special', 'tactic_mana_steal']),
    ('planning', True, 4, 'Pianificare', 'Planning',
     'Alla fine di ciascun turno, se hai almeno due carte nella tua mano prima di pescare, pesca come se il tuo '
     'limite di carte in mano fosse più alto di 1.', ['special', 'tactic_planning']),
    ('great_start', True, 5, 'Grande Inizio', 'Great Start',
     'Quando prendi questa Tattica, pesca immediatamente 2 carte.', ['draw', 2]),
    ('the_right_moment', True, 6, 'Il Momento Giusto', 'The Right Moment',
     'Una volta in questo Giorno durante il tuo turno, puoi annunciare che farai un altro turno immediatamente '
     'dopo questo. Se lo fai, gira questa carta a faccia in giù.', ['special', 'tactic_right_moment']),
    ('from_the_dusk', False, 1, 'Dal Crepuscolo', 'From the Dusk', '', []),
    ('long_night', False, 2, 'Una Lunga Notte', 'Long Night',
     'Una volta in questa Notte, se il tuo mazzo Impresa è vuoto, puoi mescolare la tua pila degli scarti e '
     'rimettere 3 carte a caso nel tuo mazzo Impresa. Quindi gira questa carta a faccia in giù.',
     ['special', 'tactic_long_night']),
    ('mana_search', False, 3, 'Cercare Mana', 'Mana Search',
     'Una volta per turno, prima di utilizzare mana dalla Riserva, puoi ritirare fino a due dadi mana nella '
     'Riserva. Quando scegli i dadi da ritirare, devi prima prendere i dadi d\'oro (esauriti), se ce ne sono.',
     ['special', 'tactic_mana_search']),
    ('midnight_meditation', False, 4, 'Meditazione di Mezzanotte', 'Midnight Meditation',
     'Una volta in questa Notte, prima di qualsiasi tuo turno, puoi rimescolare fino a 5 carte (incluse le '
     'Ferite) dalla tua mano nel tuo mazzo Impresa e quindi pescare altrettante carte. Poi, gira questa carta a '
     'faccia in giù.', ['special', 'tactic_midnight_meditation']),
    ('preparation', False, 5, 'Preparazione', 'Preparation',
     'Quando prendi questa Tattica, cerca nel tuo mazzo una carta qualsiasi e aggiungila alla tua mano, quindi '
     'rimescola il tuo mazzo.', ['special', 'tactic_preparation']),
    ('sparing_power', False, 6, 'Risparmiare Potere', 'Sparing Power',
     'Una volta prima dell\'inizio di ciascuno dei tuoi turni, scegli uno tra: metti la carta in cima al tuo mazzo '
     'Impresa a faccia in giù sotto questa carta, oppure gira questa carta a faccia in giù e metti tutte le carte '
     'Impresa sotto di essa nella tua mano.', ['special', 'tactic_sparing_power']),
]
SPECIALS = {
    'tactic_rethink': 'Alla scelta della tattica (fase tattiche, prima del primo turno): il giocatore sceglie da 0 a 3 '
                      'carte della mano (anche Ferite) e le scarta; pesca altrettante carte; poi rimescola la pila '
                      'degli scarti (incluse le carte appena scartate) nel mazzo Impresa.',
    'tactic_mana_steal': 'Alla scelta: prende un dado della Fonte che mostra un colore base (rosso/blu/verde/bianco) e '
                         'lo tiene sulla carta (non è più nella Fonte, non viene rilanciato a fine turno degli altri). '
                         'In un qualsiasi proprio turno di questo Giorno può usarlo come mana di quel colore (in '
                         'aggiunta al normale dado della Fonte); se lo usa, a fine turno il dado viene rilanciato e '
                         'rimesso nella Fonte e la tattica non ha più effetto.',
    'tactic_planning': 'A fine turno di ogni turno del round: se prima di pescare il giocatore ha almeno 2 carte in '
                       'mano, pesca fino a limite di mano + 1.',
    'tactic_right_moment': 'Una volta in questo Giorno, durante il proprio turno: il giocatore annuncia un turno extra; '
                           'appena finito il turno corrente ne gioca subito un altro (prima del giocatore successivo). '
                           'Poi la tattica è girata (usata).',
    'tactic_long_night': 'Una volta in questa Notte, all\'inizio del proprio turno se il mazzo Impresa è vuoto: '
                         'mescola la pila degli scarti e mette 3 carte a caso nel mazzo Impresa (il resto resta negli '
                         'scarti). Poi la tattica è girata.',
    'tactic_mana_search': 'Una volta per turno, prima di prendere mana dalla Fonte: il giocatore può rilanciare fino a '
                          '2 dadi della Fonte non presi (se ci sono dadi oro esauriti di Notte, cioè oro, deve '
                          'sceglierli per primi).',
    'tactic_midnight_meditation': 'Una volta in questa Notte, prima di un proprio turno: il giocatore sceglie da 0 a 5 '
                                  'carte della mano (anche Ferite), le rimescola nel mazzo Impresa e pesca altrettante '
                                  'carte. Poi la tattica è girata.',
    'tactic_preparation': 'Alla scelta: il giocatore guarda il proprio mazzo Impresa, sceglie una carta e la mette in '
                          'mano; poi rimescola il mazzo.',
    'tactic_sparing_power': 'Prima dell\'inizio di ciascun proprio turno (obbligatorio scegliere): (a) mette la carta '
                            'in cima al mazzo Impresa, coperta, sotto questa tattica (accumulo) — se il mazzo è vuoto '
                            'questa opzione non è possibile; oppure (b) gira la tattica e mette in mano tutte le carte '
                            'accumulate sotto di essa. Le carte accumulate non contano come mazzo.',
}


def build_tactics():
    tacs = {}
    specials = {}
    for i, (tid, day, n, nit, nen, txt, eff) in enumerate(TACTICS):
        guid = TACTIC_GUIDS[i]
        o = BY_GUID[guid]
        rec = {'id': tid, 'day': day, 'number': n, 'name_it': nit, 'name_en': nen, 'text_it': txt,
               'effect': eff, 'img': 'assets/cards/tactic_%s.webp' % tid, 'guid': guid,
               'when': 'pick' if tid in ('rethink', 'mana_steal', 'great_start', 'preparation') else
               ('none' if not eff else 'round')}
        src = cache_file(o['img'])
        save_webp(Image.open(src), rec['img'], max_side=700, asset_id='tactic_' + tid)
        if eff and eff[0] == 'special':
            specials[eff[1]] = {'desc': SPECIALS[eff[1]], 'used_by': [tid]}
        tacs[tid] = rec
    back_d = cache_file(BY_GUID[TACTIC_GUIDS[0]]['img2'])
    back_n = cache_file(BY_GUID[TACTIC_GUIDS[6]]['img2'])
    if back_d:
        save_webp(Image.open(back_d), 'assets/cards/tactic_back_day.webp', max_side=700, asset_id='tactic_back_day')
    if back_n:
        save_webp(Image.open(back_n), 'assets/cards/tactic_back_night.webp', max_side=700,
                  asset_id='tactic_back_night')
    write_json('data/tactics.json', {'_notes': {
        'order': 'Il numero della tattica determina l\'ordine di turno (più basso = primo). Mattiniero e Dal '
                 'Crepuscolo non hanno effetto.',
        'when': 'pick = effetto immediato alla scelta; round = effetto disponibile durante il round; none.',
        'terms': 'Sulle carte italiane la Fonte è chiamata "Riserva" e il mazzo "mazzo Impresa".'},
        'tactics': tacs})
    write_json('data/specials_world.json', specials)
    return tacs


# =================================================================================== RULES
def build_rules():
    levels = []
    fame = [0, 3, 8, 15, 24, 35, 48, 63, 80, 99]
    stats = {1: (2, 5, 1), 3: (3, 5, 2), 5: (3, 6, 3), 7: (4, 6, 4), 9: (4, 7, 5)}
    for lv in range(1, 11):
        a, h, c = stats[lv if lv % 2 else lv - 1]
        levels.append({'level': lv, 'fame': fame[lv - 1], 'armor': a, 'hand': h, 'command': c,
                       'reward': 'skill_aa' if lv % 2 == 0 else ('stats' if lv > 1 else '')})
    rep = {str(k): v['repDisplay'] for k, v in sorted(REPUTATION.items())}
    rep_bonus = {}
    for k, v in rep.items():
        rep_bonus[k] = None if v == 'No Interaction' else int(v)
    rules = {
        '_notes': 'Valori verificati sul regolamento italiano (Ultimate Edition), sulla Guida e sulle carte '
                  'descrizione sito del modulo. Fama oltre 99: il tracciato continua (ogni riga successiva +2 '
                  'Fama richiesta in più); il livello massimo è 10.',
        'levels': levels,
        'level_rewards': 'Livelli pari (2,4,6,8,10): 1 Abilità (tra 2 pescate dalla propria pila; in competitiva '
                         'anche dall\'offerta comune — allora si prende l\'AA più in basso) + 1 Azione Avanzata '
                         'dall\'offerta. Livelli dispari (3,5,7,9): si gira il gettone Livello -> nuove armatura, '
                         'limite di mano e +1 Comando.',
        'reputation': {'min': -7, 'max': 7, 'start': 0, 'influence_bonus': rep_bonus,
                       'no_interaction_at': -7},
        'terrain_cost': {
            'day': {'plains': 2, 'hills': 3, 'forest': 3, 'wasteland': 4, 'desert': 5, 'swamp': 5,
                    'lake': None, 'mountain': None, 'ocean': None, 'city': 2},
            'night': {'plains': 2, 'hills': 3, 'forest': 5, 'wasteland': 4, 'desert': 3, 'swamp': 5,
                      'lake': None, 'mountain': None, 'ocean': None, 'city': 2},
            '_note': 'null = invalicabile. Lo spazio città costa 2 qualunque sia il terreno.'},
        'explore_cost': 2,
        'source_dice': {'count': 'players+2', 'min_basic_fraction': 0.5,
                        'note': 'I giocatori Neutrali non contano. Almeno metà dei dadi deve mostrare colori base: '
                                'si rilanciano i dadi oro/nero finché non è così.'},
        'mana': {'gold': 'di Giorno vale qualsiasi colore base; di Notte inutilizzabile (esaurito)',
                 'black': 'solo di Notte e solo per l\'effetto potenziato degli Incantesimi (al posto del nero)',
                 'dice_per_turn': 1},
        'crystal_max': 3, 'start_crystals': 0,
        'hand_limit_bonus': {'own_keep': '+1 per ogni Castello posseduto se su/adiacente a un proprio castello',
                             'city_leader': 2, 'city_shield': 1},
        'wound_pile': None,
        'offers': {'units': 'players+2 (solo Regolari finché non è rivelata una tessera Principale; poi alternando '
                            'Élite, Regolare, Élite…) + 1 Azione Avanzata per ogni monastero non bruciato',
                   'aa': 3, 'spells': 3, 'monastery_aa_cost': 6},
        'round_reset': 'Inizio round: gira Giorno/Notte, rilancia la Fonte, nuova offerta Unità (le vecchie in '
                       'fondo ai mazzi), l\'AA più in basso va in fondo al mazzo e se ne aggiunge una nuova in cima '
                       '(idem Incantesimi), si raccolgono le tattiche, si preparano Unità e abilità.',
        'knockout': 'Colpo di Grazia: se in un combattimento l\'Eroe riceve ferite in mano ≥ limite di mano non '
                    'modificato (gettone Livello), scarta subito tutte le carte non-Ferita dalla mano.',
        'sites': {
            'village': {'heal_cost': 3, 'plunder': {'rep': -1, 'draw': 2, 'when': 'turno di un altro giocatore '
                        '(una volta tra due propri turni)'}, 'recruit': 'village'},
            'monastery': {'heal_cost': 2, 'aa_cost': 6, 'on_reveal': 'aggiunge 1 AA dal mazzo all\'offerta Unità',
                          'burn': {'rep': -3, 'enemy': 'violet', 'units': False, 'reward': ['artifact'],
                                   'after': 'distrutto (Scudo)'}, 'recruit': 'monastery'},
            'keep': {'garrison': 'gray', 'face_down_until_adjacent_day': True, 'assault_rep': -1,
                     'fortified': True, 'owner_reward': 'conquista (Scudo), poi reclutamento e +1 mano',
                     'other_owner': 'difensore grigio casuale; metà Fama (arrotondata per eccesso)'},
            'mage_tower': {'garrison': 'violet', 'face_down_until_adjacent_day': True, 'assault_rep': -1,
                           'fortified': True, 'reward': ['spell'], 'spell_cost': 7, 'spell_mana': 'colore dell\'Incantesimo'},
            'dungeon': {'enemy': 'brown', 'night_rules': True, 'units': False,
                        'reward': 'tira un dado mana: oro o nero = Incantesimo, altrimenti Artefatto',
                        'revisit': 'nemico marrone casuale, solo Fama'},
            'tomb': {'enemy': 'red', 'night_rules': True, 'units': False, 'reward': ['spell', 'artifact'],
                     'revisit': 'nemico rosso casuale, solo Fama'},
            'monster_den': {'enemy': 'brown', 'reward': 'due cristalli: tira 2 dadi mana (oro = colore a scelta, nero = '
                            '+1 Fama invece del cristallo)', 'undefeated_stays': True},
            'spawning_grounds': {'enemies': ['brown', 'brown'], 'reward': 'Artefatto + 3 cristalli tirati (oro = a '
                                 'scelta, nero = +1 Fama)', 'undefeated_stays': True},
            'ruins': 'vedi ruins.json',
            'glade': {'start_turn': 'gettone mana oro di Giorno / nero di Notte',
                      'end_turn': 'può gettare via una Ferita dalla mano o dalla pila degli scarti (non è Curare)'},
            'mine': {'end_turn': 'un cristallo del colore della miniera'},
            'orcs': {'rampaging': True, 'reward_rep': 1, 'challenge_from_adjacent': True},
            'draconum': {'rampaging': True, 'reward_rep': 2, 'challenge_from_adjacent': True},
            'city': 'vedi cities.json',
        },
        'scoring': {
            'greatest_knowledge': {'name_it': 'Il Più Grande Sapiente', 'per_spell': 2, 'per_aa': 1, 'title': 3, 'tie': 1},
            'greatest_loot': {'name_it': 'Il Più Grande Predone', 'per_artifact': 2, 'per_2_crystals': 1, 'title': 3, 'tie': 1},
            'greatest_leader': {'name_it': 'Il Più Grande Leader', 'per_unit_level': 1,
                                'wounded_unit': 'metà livello per difetto', 'title': 3, 'tie': 1},
            'greatest_conqueror': {'name_it': 'Il Più Grande Conquistatore', 'per_shield_keep_tower_monastery': 2,
                                   'title': 3, 'tie': 1},
            'greatest_adventurer': {'name_it': 'Il Più Grande Avventuriero', 'per_shield_adventure_site': 2,
                                    'title': 3, 'tie': 1},
            'greatest_beating': {'name_it': 'Il Più Grande Sconfitto', 'per_wound_in_deck': -2, 'title': -3,
                                 'tie': -1},
            'cities': {'leader': 7, 'shield_not_leader': 4, 'most_city_fame_title': 5, 'tie': 2},
            '_note': 'Titoli solo in partite competitive; in parità ognuno prende il valore "tie" (salvo se tutti a 0). '
                     'Siti avventura = sotterraneo, tomba, tana, terreni di nidificazione, rovine, (labirinto/dedalo).'},
        'dummy': {
            'crystals': 'tre cristalli dei colori delle sfere sulla carta Eroe (vedi heroes.json dummy_crystals)',
            'turn': 'Mazzo vuoto -> annuncia fine round. Altrimenti gira 3 carte negli scarti; se ha cristalli del '
                    'colore dell\'ultima carta girata, gira altrettante carte in più.',
            'round_start': 'l\'AA tolta dal fondo dell\'offerta va nel suo mazzo (poi rimescolato); per l\'Incantesimo '
                           'tolto riceve un cristallo del suo colore (può superare 3).',
            'tactic': 'secondo lo scenario (solitario: sceglie a caso dopo il giocatore; coop: sceglie a caso per primo)',
            'skills_solo': 'Quando l\'Eroe ottiene un gettone Abilità, si rivela anche un\'Abilità del Neutrale e la '
                           'si mette nell\'offerta Abilità Comune (se la scegli, prendi l\'AA più in basso).'},
    }
    write_json('data/rules.json', rules)
    return rules


# =================================================================================== SCENARIOS
SCENARIOS = {
    'first_recon': {
        'name_it': 'La Prima Ricognizione', 'name_en': 'First Reconnaissance', 'players': [2, 4], 'solo_variant': True,
        'type': 'leggermente competitivo', 'set': 'base', 'rounds': 3, 'rounds_solo': 4,
        'map': {'shape': 'wedge', 'start_tile': 'start_a', 'setup_reveal': 2},
        'tiles': {'country': {'1': 8, '2': 8, '3': 9, '4': 11}, 'country_order': 'by_number',
                  'core_noncity': 2, 'city': 1},
        'city_levels': None, 'cities_enterable': False, 'dummy': 'solo',
        'special': ['fame_per_tile_revealed:1', 'no_pvp', 'no_elite_units', 'hide_offers_until_needed'],
        'end': 'Quando un giocatore rivela una città, tutti (lui compreso) hanno un ultimo turno; se il round '
               'finisce prima, il gioco termina subito. Altrimenti termina alla fine del 3º round.',
        'scoring': 'standard', 'titles': True, 'titles_solo': False,
        'desc_it': 'Scenario introduttivo, consigliato per la prima partita. 3 Round (2 Giorni e 1 Notte), da 2 a 4 '
                   'giocatori (variante in solitario: 8 tessere Campagna, 4 Round, giocatore Neutrale, nessun '
                   'titolo). Mappa a cuneo con la tessera iniziale A. Mazzo tessere: le tessere Campagna in ordine '
                   'di numero (1 in cima; 8/9/11 tessere con 2/3/4 giocatori) sopra 1 tessera città e 2 tessere '
                   'Principali non-città mescolate. Le città non possono essere conquistate né vi si può entrare. '
                   'Si ottiene 1 Fama per ogni nuova tessera rivelata. Niente combattimento tra giocatori, niente '
                   'Unità d\'Élite. Quando qualcuno rivela la città, tutti hanno un ultimo turno. Vince chi ha più '
                   'Fama dopo il conteggio dei Successi standard.'},
    'full_conquest': {
        'name_it': 'Conquista Totale', 'name_en': 'Full Conquest', 'players': [2, 4], 'type': 'competitivo',
        'set': 'base', 'rounds': 6,
        'map': {'shape': {'2': 'wedge', '3': 'wedge', '4': 'open'}, 'start_tile': {'2': 'start_a', '3': 'start_a',
                '4': 'start_b'}, 'setup_reveal': {'wedge': 2, 'open': 3}},
        'tiles': {'country': {'2': 8, '3': 9, '4': 11}, 'core_noncity': 'players-1', 'city': 'players'},
        'city_levels': {'all': 4}, 'dummy': None, 'special': [],
        'end': 'Quando tutte le città sono conquistate, tutti (anche chi ha conquistato l\'ultima) hanno un ultimo '
               'turno; se il round finisce durante questo giro il gioco termina subito. Altrimenti fine del 6º round.',
        'scoring': 'standard+cities', 'titles': True,
        'desc_it': 'Scenario standard competitivo. 6 Round (3 Giorni e 3 Notti), da 2 a 4 giocatori. Mappa a cuneo '
                   '(2-3 giocatori) o completamente aperta (4). Tessere Campagna 8/9/11, tessere città pari al '
                   'numero di giocatori, tessere Principali non-città una in meno. Ogni città rivelata è di livello 4. '
                   'Quando tutte le città sono conquistate, tutti hanno un ultimo turno. Punteggio: Successi standard '
                   '+ città (7 Fama per ogni città di cui si è leader, 4 per ogni città dove si ha almeno uno Scudo '
                   'senza esserne leader; +5 al Più Grande Conquistatore di città, +2 in caso di parità). Vince chi ha '
                   'più Fama.'},
    'blitz_conquest': {
        'name_it': 'Conquista Blitz', 'name_en': 'Blitz Conquest', 'players': [2, 4], 'type': 'competitivo',
        'set': 'base', 'rounds': 4,
        'map': {'shape': {'2': 'wedge', '3': 'wedge', '4': 'open4'}, 'start_tile': {'2': 'start_a', '3': 'start_a',
                '4': 'start_b'}, 'setup_reveal': {'wedge': 2, 'open4': 3}},
        'tiles': {'country': {'2': 6, '3': 7, '4': 9}, 'core_noncity': 'players-1', 'city': 'players'},
        'city_levels': {'all': 3}, 'dummy': None,
        'special': ['start_fame:1', 'fame_bonus_per_track_line:1', 'start_rep:2', 'extra_source_die:1',
                    'extra_unit_offer:1'],
        'end': 'Come Conquista Totale (4 round).', 'scoring': 'standard+cities', 'titles': True,
        'desc_it': 'Versione breve della Conquista. 4 Round (2 Giorni e 2 Notti), da 2 a 4 giocatori. Cuneo (2-3) o '
                   'aperta limitata a 4 colonne (4). Tessere Campagna 6/7/9, città pari ai giocatori, non-città una in '
                   'meno; città di livello 3. Si inizia con Fama 1 e Reputazione +2; ogni volta che si supera una linea '
                   'del tracciato della Fama si ottiene 1 Fama extra; un dado in più nella Fonte e un\'Unità in più '
                   'nell\'offerta. Punteggio come Conquista Totale.'},
    'solo_conquest': {
        'name_it': 'Conquista in Solitario', 'name_en': 'Solo Conquest', 'players': [1, 1], 'type': 'solitario',
        'set': 'base', 'rounds': 6,
        'map': {'shape': 'wedge', 'start_tile': 'start_a', 'setup_reveal': 2},
        'tiles': {'country': {'1': 7}, 'core_noncity': 2, 'city': 2},
        'city_levels': {'order': [5, 8]}, 'dummy': 'neutral',
        'special': ['remove_competitive_spells', 'remove_interactive_skill', 'tactics_player_first_dummy_random',
                    'tactics_removed_after_round', 'dummy_no_final_turn'],
        'end': 'Quando tutte le città sono conquistate hai ancora un ultimo turno (il Neutrale no). Altrimenti fine '
               'del 6º round.',
        'scoring': 'solo', 'titles': False,
        'score_extra': {'per_city': 10, 'all_cities': 15, 'per_round_early': 30, 'per_dummy_deck_card': 1,
                        'round_end_not_announced': 5},
        'desc_it': 'Partita in solitario. 6 Round (3 Giorni e 3 Notti). Mappa a cuneo con tessera A; 7 tessere '
                   'Campagna, 2 tessere città e 2 tessere Principali non-città. La prima città rivelata è di livello 5, '
                   'la seconda di livello 8. C\'è un giocatore Neutrale. Si rimuovono i quattro Incantesimi competitivi '
                   '(109-112) e l\'Abilità interattiva dalla propria pila. Tattiche: scegli sempre per primo, il '
                   'Neutrale ne prende una a caso tra le rimaste; alla fine di ogni Giorno o Notte entrambe le tattiche '
                   'usate sono rimosse dal gioco. Vittoria se conquisti tutte le città. Punteggio: Fama + Successi '
                   'standard (senza titoli) + 10 per città conquistata, +15 se tutte, +30 per ogni round risparmiato, '
                   '+1 per ogni carta ancora nel mazzo del Neutrale, +5 se nell\'ultimo round la fine non era ancora '
                   'stata annunciata.'},
    'coop_conquest': {
        'name_it': 'Cooperazione Totale', 'name_en': 'Full Cooperation', 'players': [2, 3], 'type': 'cooperativo',
        'set': 'base', 'rounds': 6,
        'map': {'shape': 'open', 'start_tile': 'start_b', 'setup_reveal': 3},
        'tiles': {'country': {'2': 8, '3': 10}, 'core_noncity': 'players', 'city': 'players+1'},
        'city_levels': {'all': 5, 'last': {'2': 8, '3': 11}}, 'dummy': 'neutral',
        'special': ['remove_competitive_spells', 'remove_interactive_skill', 'tactics_dummy_first_random',
                    'remove_one_player_tactic_per_round', 'team_rules_single_team', 'dummy_no_final_turn'],
        'end': 'Quando tutte le città sono conquistate, tutti tranne il Neutrale hanno un ultimo turno. Altrimenti '
               'fine del 6º round.',
        'scoring': 'coop', 'titles': False,
        'score_extra': {'per_city': 10, 'every_player_leader': 10, 'all_cities': 15, 'per_round_early': 30,
                        'per_dummy_deck_card': 1, 'round_end_not_announced': 5},
        'desc_it': 'Scenario cooperativo standard: 2 o 3 giocatori contro le città. 6 Round. Mappa completamente aperta '
                   '(tessera B). Tessere Campagna 8/10, tessere città una in più dei giocatori, non-città pari ai '
                   'giocatori. Città di livello 5, tranne l\'ultima rivelata: livello 8 (2 giocatori) o 11 (3). C\'è un '
                   'giocatore Neutrale che prende per primo una tattica a caso; a fine Giorno/Notte si rimuove dal '
                   'gioco una delle tattiche usate dai giocatori. Si rimuovono gli Incantesimi competitivi e '
                   'un\'Abilità interattiva da ogni pila. Vittoria comune se tutte le città sono conquistate. Punteggio '
                   'di squadra: Fama più bassa + migliori Successi per categoria (senza titoli) + 10 per città, +10 se '
                   'ogni giocatore è leader di almeno una città, +15 se tutte, +30 per round risparmiato, +1 per carta '
                   'nel mazzo del Neutrale, +5 se la fine dell\'ultimo round non era annunciata.'},
    'coop_blitz': {
        'name_it': 'Cooperazione Blitz', 'name_en': 'Blitz Cooperation', 'players': [2, 3], 'type': 'cooperativo',
        'set': 'base', 'rounds': 4,
        'map': {'shape': 'open', 'start_tile': 'start_b', 'setup_reveal': 3},
        'tiles': {'country': {'2': 7, '3': 8}, 'core_noncity': 'players-1', 'city': 'players'},
        'city_levels': {'order': {'2': [5, 8], '3': [5, 8, 11]}}, 'dummy': 'neutral',
        'special': ['remove_competitive_spells', 'remove_interactive_skill', 'tactics_dummy_first_random',
                    'remove_one_player_tactic_per_round', 'team_rules_single_team', 'start_fame:1',
                    'fame_bonus_per_track_line:1', 'start_rep:2', 'extra_source_die:1', 'extra_unit_offer:1'],
        'end': 'Come Cooperazione Totale (4 round).', 'scoring': 'coop', 'titles': False,
        'score_extra': {'per_city': 10, 'every_player_leader': 10, 'all_cities': 15, 'per_round_early': 30,
                        'per_dummy_deck_card': 1, 'round_end_not_announced': 5},
        'desc_it': 'Versione breve della Cooperazione Totale: 4 Round (2 Giorni e 2 Notti), 2 o 3 giocatori. Tessere '
                   'Campagna 7/8, tessere città pari ai giocatori, non-città una in meno; le città, nell\'ordine di '
                   'rivelazione, sono di livello 5 e 8 (2 giocatori) o 5, 8 e 11 (3). Si inizia con Fama 1 e '
                   'Reputazione +2, +1 Fama ogni volta che si supera una linea del tracciato, un dado in più nella '
                   'Fonte e un\'Unità in più nell\'offerta.'},
}


def build_scenarios():
    doc = {'_notes': {
        'source': 'Manuale degli Scenari (regolamento italiano pp. 14-22). Altri scenari presenti nel manuale ma non '
                  'trascritti: Liberazione delle Miniere, Le Notti del Druido, I Signori del Sotterraneo, Conquista '
                  'e Mantieni, Solo una Tornata (alcuni richiedono espansioni).',
        'deck': 'Mazzo tessere: tessere Campagna (retro verde) prese a caso (in Prima Ricognizione in ordine di '
                'numero) messe sopra le tessere Principali scelte a caso (città e non-città separatamente) e '
                'mescolate tra loro. All\'inizio si rivelano 2 tessere (cuneo, A) o 3 (aperta, B) adiacenti a quella '
                'iniziale.',
        'shapes': 'wedge = cuneo (tessera A); le tessere Principali (marroni) non possono essere piazzate sulla '
                  'linea costiera (colonne più a sinistra e più a destra del cuneo). open = completamente aperta '
                  '(tessera B), al massimo 5 colonne parallele di tessere; open4/open3 = aperta limitata a 4 o 3 '
                  'colonne (con 4 colonne si apre di più a destra).',
        'tiles_counts': 'country: {numero giocatori: tessere}; core_noncity/city: numero o formula su "players".',
        'city_levels': '{"all": n} tutte uguali; {"order": [..]} nell\'ordine di rivelazione; {"last": {...}} '
                       'livello dell\'ultima rivelata.',
        'dummy': 'neutral = giocatore Neutrale (vedi rules.json dummy); solo = solo nella variante in solitario.',
        'coop_players': 'Il manuale prevede le cooperative solo per 2-3 giocatori (4 solo con un secondo mazzo '
                        'Neutrale).'},
        'scenarios': SCENARIOS}
    write_json('data/scenarios.json', doc)


# =================================================================================== HEROES + MODELS
HERO_IT = {'arythea': 'Arythea', 'goldyx': 'Goldyx', 'norowas': 'Norowas', 'tovak': 'Tovak',
           'wolfhawk': 'Wolfhawk', 'krang': 'Krang', 'braevalar': 'Braevalar'}
HERO_SET = {'arythea': 'base', 'goldyx': 'base', 'norowas': 'base', 'tovak': 'base', 'wolfhawk': 'll',
            'krang': 'krang', 'braevalar': 'tezla'}


def clean_obj(src, dst):
    """Copia un OBJ togliendo mtllib/usemtl (la texture si assegna da codice) e calcola il bounding box."""
    mn = [1e9] * 3
    mx = [-1e9] * 3
    nv = nf = 0
    lines = []
    with open(src, encoding='utf-8', errors='ignore') as f:
        for line in f:
            if line.startswith(('mtllib', 'usemtl')):
                continue
            if line.startswith('v '):
                p = line.split()
                for i in range(3):
                    v = float(p[i + 1])
                    mn[i] = min(mn[i], v); mx[i] = max(mx[i], v)
                nv += 1
            elif line.startswith('f '):
                nf += 1
            lines.append(line)
    if not NO_IMAGES:
        with open(out(dst), 'w', encoding='utf-8') as f:
            f.write('# Pulito da tools/build_world.py (senza materiali)\n')
            f.writelines(lines)
    return {'min': [round(v, 3) for v in mn], 'max': [round(v, 3) for v in mx], 'verts': nv, 'faces': nf}


MODELS = {}


def export_model(name, obj_guid, tex_max=1024):
    o = BY_GUID[obj_guid]
    src = cache_file(o.get('mesh'), MDL_DIR)
    if not src:
        print('!! modello mancante', name)
        return None
    rel = 'assets/models/%s.obj' % name
    info = clean_obj(src, rel)
    ASSETS['model_' + name] = rel
    tex = cache_file(o.get('diffuse'))
    rec = {'obj': rel, 'bbox': info, 'tts_scale': o['scale'], 'up': 'y'}
    if tex:
        rec['texture'] = save_webp(Image.open(tex), 'assets/models/%s.webp' % name, max_side=tex_max,
                                   asset_id='model_tex_' + name)
    MODELS[name] = rec
    return rec


def build_heroes():
    heroes = {}
    for k in KNIGHTS:
        mage = k['mage']
        hid = mage.lower()
        if hid not in HERO_IT:
            continue
        cr = [c.lower() for c in k['crystals']]
        rec = {'id': hid, 'name_it': HERO_IT[hid], 'name_en': mage, 'set': HERO_SET[hid], 'colour': cr[0],
               'dummy_crystals': [cr[0], cr[0], cr[1]]}
        fig = export_model('hero_' + hid, k['model'])
        if fig:
            rec['figure'] = {'obj': fig['obj'], 'texture': fig.get('texture'), 'bbox': fig['bbox']}
        # gettone eroe (ottagonale), sagoma (standee), scudo, segnalino, gettone ordine di round
        tok = BY_GUID.get(k['token'])
        if tok and cache_file(tok.get('img')):
            rec['token'] = save_webp(Image.open(cache_file(tok['img'])), 'assets/tokens/hero_%s_token.webp' % hid,
                                     max_side=512, asset_id='hero_token_' + hid)
        st = BY_GUID.get(k['standee'])
        if st and cache_file(st.get('diffuse')):
            rec['standee'] = save_webp(Image.open(cache_file(st['diffuse'])),
                                       'assets/tokens/hero_%s_standee.webp' % hid, max_side=512,
                                       asset_id='hero_standee_' + hid)
        comp_path = '/%s (Components)' % mage
        for o in OBJS:
            if not o['path'].startswith(comp_path):
                continue
            if o['nick'] == 'Shield' and 'shield' not in rec and cache_file(o.get('diffuse')):
                rec['shield'] = save_webp(Image.open(cache_file(o['diffuse'])), 'assets/tokens/hero_%s_shield.webp'
                                          % hid, max_side=512, asset_id='hero_shield_' + hid)
            elif o['nick'].endswith('Marker') and 'marker' not in rec and cache_file(o.get('diffuse')):
                rec['marker'] = save_webp(Image.open(cache_file(o['diffuse'])), 'assets/tokens/hero_%s_marker.webp'
                                          % hid, max_side=512, asset_id='hero_marker_' + hid)
            elif o['nick'].endswith('Turn Order Token') and cache_file(o.get('img')):
                rec['turn_order'] = save_webp(Image.open(cache_file(o['img'])),
                                              'assets/tokens/hero_%s_order.webp' % hid, max_side=512,
                                              asset_id='hero_order_' + hid)
        # carta Eroe (4x2) e carta descrizione abilità
        for c in CARDS.values():
            if c['deck'] == comp_path and c['nw'] == 4 and c['nh'] == 2:
                sys.path.insert(0, os.path.join(ROOT, 'tools'))
                from card_index import crop
                rec['card'] = save_webp(crop(c, 'it'), 'assets/tokens/hero_%s_card.webp' % hid, max_side=700,
                                        asset_id='hero_card_' + hid)
                break
        heroes[hid] = rec
    # città
    for color, guid in ENV['cityModel'].items():
        export_model('city_' + color, guid)
    # gettoni comuni: retro dei comandi, dado mana
    dice = BY_GUID.get('2b5a39')
    if dice and cache_file(dice.get('img')):
        save_webp(Image.open(cache_file(dice['img'])), 'assets/tokens/mana_die.webp', max_side=1024,
                  asset_id='mana_die')
    write_json('data/heroes.json', {'_notes': {
        'colour': 'Colore principale (sfere sulla carta Eroe: due del primo colore e una del secondo). '
                  'dummy_crystals = cristalli iniziali del giocatore Neutrale con questo eroe.',
        'figure': 'OBJ con Y in alto, base centrata nell\'origine; bbox in unità del modello (raggio della base '
                  '≈1.04, altezza ≈2.4–3.0). In TTS la figura è scalata a 0.9 e una tessera (scala 2.25) misura '
                  '≈7.2 unità di larghezza: il raggio di un esagono in TTS ≈1.38 unità → una figura alta ≈2.4 unità '
                  'è alta ≈1.7 raggi di esagono. Texture da assegnare in codice (materiali rimossi).',
        'sets': 'base = gioco base; wolfhawk = Lost Legion (set ll), krang = espansione Krang; tezla = Shades of Tezla.'},
        'heroes': heroes, 'models': MODELS})
    return heroes


# =================================================================================== SITE CARDS
SITE_CARDS = {'orcs': 0, 'draconum': 1, 'monastery': 2, 'village': 3, 'walls': 4, 'ruins': 5, 'mine_glade': 6,
              'deep_mine_camp': 7, 'dungeon': 8, 'tomb': 9, 'mage_tower': 10, 'keep': 11, 'maze': 12,
              'labyrinth': 13, 'monster_den': 14, 'spawning_grounds': 15, 'necropolis': 16, 'hidden_valley': 17,
              'movement_costs': 24, 'city': 25, 'volkare_camp': 26}


def build_site_cards():
    for sid, idx in SITE_CARDS.items():
        save_webp(site_card(idx), 'assets/tokens/site_%s.webp' % sid, max_side=1000, asset_id='site_' + sid)


def main():
    tiles = build_tiles()
    enemies = build_enemies()
    ruins = build_ruins(enemies)
    cities = build_cities()
    tactics = build_tactics()
    build_rules()
    build_scenarios()
    heroes = build_heroes()
    build_site_cards()
    write_json('data/assets.json', dict(sorted(ASSETS.items())))
    print('tessere', len(tiles), '| nemici', len(enemies), '| rovine', len(ruins), '| città', len(cities),
          '| tattiche', len(tactics), '| eroi', len(heroes), '| modelli', len(MODELS), '| asset', len(ASSETS))


if __name__ == '__main__':
    main()
