#!/usr/bin/env bash
# Start jack_mixer + VBAN ontvanger/zender + qpwgraph (blokken en draden).
# Draait los van de terminal (venster sluiten mag).
#
# Knoppen (app-menu):  Mixer starten / Mixer opslaan / Mixer stoppen
#   opslaan: faders, draden en plek van de blokken
#   stoppen: eerst alles opslaan, dan alles netjes afsluiten
# qpwgraph met het kruisje sluiten = ook stoppen (en alles wordt opgeslagen).

# ---- INSTELLINGEN ----------------------------------------------------------
VBAN_IP="192.168.1.2"     # IP van de andere computer met VBAN
VBAN_PORT="6980"          # standaard VBAN-poort
VBAN_IN_NAME="test-vban"  # streamnaam die we ONTVANGEN (max 16 tekens)
VBAN_OUT_NAME="test-vban" # streamnaam die we VERSTUREN (max 16 tekens)

MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIXER_FILE="$MAP/mixer.xml"                    # kanalen en faders (jack_mixer)
# Draden: $MAP/mixer-verbindingen.txt (beheerd door mixer.py)
# Plek van de blokken: ~/.config/rncbc.org/qpwgraph.conf (beheerd door qpwgraph)
# ----------------------------------------------------------------------------

set -u
pids=()
jm_pid=""   # jack_mixer, alleen gezet als hij met mixer.xml is gestart
MIXER_PY="$MAP/mixer.py"
HERSTART_VLAG="$MAP/.qpwgraph-herstart"   # gezet door 'opslaan': qpwgraph opnieuw openen

for c in pw-jack pw-link jack_mixer qpwgraph vban_receptor vban_emitter setsid python3 xprop; do
    command -v "$c" >/dev/null || { echo "FOUT: '$c' is niet geinstalleerd."; exit 1; }
done

# Loskoppelen van de terminal: anders stopt alles zodra je het terminalvenster
# sluit. Meldingen gaan naar mixer.log.
LOG="$MAP/mixer.log"
if [ "${MIXER_LOSGEKOPPELD:-}" != 1 ]; then
    MIXER_LOSGEKOPPELD=1 setsid "$MAP/$(basename "${BASH_SOURCE[0]}")" "$@" \
        >"$LOG" 2>&1 </dev/null &
    echo "Mixer gestart. Je kunt deze terminal nu gerust sluiten."
    echo "Meldingen: $LOG"
    exit 0
fi

melding() {
    echo "$1"
    command -v notify-send >/dev/null && notify-send -i audio-card "Mixer" "$1" 2>/dev/null
}

stop_alles() {
    echo "Stoppen: alles opslaan..."
    # Draden en faders opslaan zolang alles nog draait. Is jack_mixer al weg
    # (bijv. vastgelopen), dan NIET opslaan: dan zouden zijn draden ontbreken.
    if [ -n "$jm_pid" ] && kill -0 "$jm_pid" 2>/dev/null; then
        python3 "$MIXER_PY" opslaan && sleep 1
    fi
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
    rm -f "$HERSTART_VLAG"
}

# ---- Opruimen van een vorige start -----------------------------------------

# Een vorige keer gestart script stoppen. Het eigen proces, de starter en de
# eigen subshells overslaan.
for p in $(pgrep -u "$USER" -f 'start-mixer\.sh'); do
    { [ "$p" = "$$" ] || [ "$p" = "$PPID" ]; } && continue
    [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$$" ] && continue
    kill -KILL "$p" 2>/dev/null
done
pkill -u "$USER" -f 'mixer\.py bewaken'

# Oude qpwgraph netjes sluiten (zoals het kruisje), dan bewaart hij de plek
# van de blokken. Nooit geforceerd stoppen.
if pgrep -u "$USER" -x qpwgraph >/dev/null; then
    echo "Oude qpwgraph netjes sluiten..."
    python3 "$MIXER_PY" opslaan
    if ! python3 "$MIXER_PY" sluit-qpwgraph; then
        melding "qpwgraph wil niet sluiten. Staat er een vraag open in qpwgraph? Beantwoord die en probeer opnieuw."
        exit 1
    fi
fi

oud_draait() {
    pgrep -u "$USER" -x vban_receptor >/dev/null ||
    pgrep -u "$USER" -x vban_emitter >/dev/null ||
    pgrep -u "$USER" -f '(^|/)jack_mixer( |$)' >/dev/null
}
if oud_draait; then
    echo "Oude mixer-onderdelen draaien nog, die worden eerst gestopt..."
    # Een oude jack_mixer die met een bestand (-c) draait eerst laten opslaan.
    if pkill -USR1 -u "$USER" -f '(^|/)jack_mixer( .*)? -c '; then
        sleep 1
    fi
    pkill -u "$USER" -x vban_receptor
    pkill -u "$USER" -x vban_emitter
    pkill -u "$USER" -f '(^|/)jack_mixer( |$)'
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        oud_draait || break
        sleep 0.5
    done
    if oud_draait; then
        melding "FOUT: oude mixer-onderdelen willen niet stoppen."
        pgrep -a -u "$USER" -f 'vban_receptor|vban_emitter|jack_mixer'
        exit 1
    fi
fi
rm -f "$HERSTART_VLAG"

trap stop_alles EXIT INT TERM

# ---- Starten ----------------------------------------------------------------

# Geen mixer.xml? Neem dan het nieuwste bestand dat jack_mixer zelf op zijn
# standaardplek heeft opgeslagen, en kopieer dat naar mixer.xml.
if [ ! -f "$MIXER_FILE" ]; then
    nieuwste="$(ls -t "$HOME/.local/share/jack_mixer/"*.xml 2>/dev/null | head -n 1)"
    if [ -n "$nieuwste" ]; then
        echo "mixer.xml ontbrak, overgenomen van $nieuwste"
        cp "$nieuwste" "$MIXER_FILE"
    fi
fi

if [ -f "$MIXER_FILE" ]; then
    echo "jack_mixer starten met $MIXER_FILE..."
    pw-jack jack_mixer -c "$MIXER_FILE" & pids+=($!)
    jm_pid=$!
    # Voor de zekerheid elke 30 s stil opslaan (SIGUSR1 = Ctrl+S, zonder venster).
    ( while sleep 30; do kill -0 "$jm_pid" 2>/dev/null || exit; kill -USR1 "$jm_pid"; done ) &
    pids+=($!)
else
    echo "jack_mixer starten (leeg: $MIXER_FILE bestaat nog niet)..."
    echo "Sla jack_mixer 1x op als $MIXER_FILE, daarna gaat opslaan automatisch."
    pw-jack jack_mixer & pids+=($!)
fi

echo "VBAN ontvanger: $VBAN_IN_NAME van $VBAN_IP:$VBAN_PORT"
# -d: naam van het blok (jack-client). Elk blok een eigen naam, anders haalt
# qpwgraph de plekken van de blokken door elkaar.
pw-jack vban_receptor -i "$VBAN_IP" -p "$VBAN_PORT" -s "$VBAN_IN_NAME" -b jack -d vban-ontvanger & pids+=($!)

# vban_emitter heeft geen jack-backend; via pulseaudio verschijnt hij als blok
# "vban-zender". Het blok "vban-ontvanger" verschijnt pas zodra er echt
# VBAN-pakketten binnenkomen.
# -r 48000: gelijk aan PipeWire (geen omrekenen). Vereist de aangepaste vban
# (pulseaudio_backend.c, kleine record-buffer), anders komt het geluid in stoten van ~2s.
echo "VBAN zender: $VBAN_OUT_NAME naar $VBAN_IP:$VBAN_PORT"
PULSE_PROP="application.name=vban-zender node.name=vban-zender" \
    vban_emitter -i "$VBAN_IP" -p "$VBAN_PORT" -s "$VBAN_OUT_NAME" -b pulseaudio -r 48000 -x 1024 & pids+=($!)

# Draden terugleggen (ook later, als Firefox of de VBAN-ontvanger verschijnt)
# en verkeerde automatische koppelingen van PipeWire weghalen.
python3 "$MIXER_PY" bewaken & pids+=($!)

# qpwgraph alleen als kijk- en tekenvenster: zijn eigen patchbay uit (geen
# 'opslaan?'-vragen, geen gevecht met mixer.py) en geen systeemvak-icoon.
python3 "$MIXER_PY" qpwgraph-instellen
sleep 1
echo "qpwgraph openen..."
qpwgraph &

# Wachten tot qpwgraph dicht is. Komt dat door 'opslaan' (vlag), dan gewoon
# opnieuw openen; anders is dat het teken om alles te stoppen.
sleep 2
while true; do
    if pgrep -u "$USER" -x qpwgraph >/dev/null; then
        sleep 1
    elif [ -f "$HERSTART_VLAG" ]; then
        rm -f "$HERSTART_VLAG"
        echo "qpwgraph opnieuw openen (na opslaan)..."
        qpwgraph &
        sleep 2
    else
        break
    fi
done
