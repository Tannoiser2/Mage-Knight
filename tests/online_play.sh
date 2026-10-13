#!/bin/bash
# Prova del gioco online sul finto Firebase: host + ospite (che esce a metà e rientra), poi una
# seconda partita in cui l'ospite altera il proprio stato (deve scoprire la desincronia e rimediare).
# Uso (dalla cartella del progetto): tests/online_play.sh      Variabili: GODOT, PORT, MOCK_FLAKY
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/home/claude/tools/Godot_v4.7-stable_linux.x86_64}
PORT=${PORT:-8791}
T=$(mktemp -d)
echo "registri in $T"
python3 tests/firebase_mock.py $PORT > $T/mock.log 2>&1 &
MOCK=$!
trap "kill $MOCK 2>/dev/null" EXIT
sleep 1
export MK_DB_URL=http://127.0.0.1:$PORT/db MK_AUTH_URL=http://127.0.0.1:$PORT/signup MK_REFRESH_URL=http://127.0.0.1:$PORT/refresh
export MK_AWAY_MS=${MK_AWAY_MS:-6000}
RUN="$GODOT --headless --path . -s res://tests/online_play.gd"
FAIL=0

check() {  # $1 = nome della prova, $2.. = registri da confrontare
  local name=$1; shift
  local fps=""
  for f in "$@"; do
    local l=$(grep "MKTEST impronta" "$f" | tail -1)
    echo "  $(basename $f): ${l:-NESSUNA IMPRONTA}"
    fps="$fps
${l#MKTEST impronta }"
  done
  local n=$(echo "$fps" | sed '/^$/d' | sort -u | wc -l)
  local m=$(echo "$fps" | sed '/^$/d' | wc -l)
  if [ "$n" = "1" ] && [ "$m" = "$#" ]; then echo "OK $name: impronte uguali"; else echo "ERRORE $name: impronte diverse o mancanti"; FAIL=1; fi
}

echo "== Prova 1: partita completa, l'ospite esce alla mossa 40 e rientra"
MK_ROLE=host MK_SPEED=${MK_SPEED:-1} MK_CODEFILE=$T/code1 MK_SESSION=$T/host1.cfg $RUN > $T/host1.log 2>&1 &
H=$!
MK_ROLE=guest MK_PHASE=drop MK_DROP_AT=40 MK_CODEFILE=$T/code1 MK_SESSION=$T/guest1.cfg $RUN > $T/guest1a.log 2>&1
sleep ${BACK_AFTER:-14}
MK_ROLE=guest MK_PHASE=back MK_CODEFILE=$T/code1 MK_SESSION=$T/guest1.cfg $RUN > $T/guest1b.log 2>&1 &
G=$!
wait $H; wait $G
grep -h "MKTEST" $T/host1.log $T/guest1a.log $T/guest1b.log | grep -v "rifiutata" | head -30
check "rientro" $T/host1.log $T/guest1b.log

echo "== Prova 2: l'ospite altera il proprio stato alla mossa 30 (desincronia)"
MK_ROLE=host MK_SPEED=3 MK_CODEFILE=$T/code2 MK_SESSION=$T/host2.cfg $RUN > $T/host2.log 2>&1 &
H=$!
MK_ROLE=guest MK_CORRUPT_AT=30 MK_CODEFILE=$T/code2 MK_SESSION=$T/guest2.cfg $RUN > $T/guest2.log 2>&1
wait $H
grep -h "MKTEST" $T/guest2.log | grep -v "rifiutata" | head -20
check "desincronia" $T/host2.log $T/guest2.log
curl -s http://127.0.0.1:$PORT/stats; echo
exit $FAIL
