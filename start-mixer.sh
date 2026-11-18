#!/usr/bin/env bash
# Start jack_mixer + VBAN ontvanger/zender + qpwgraph (patchbay met blokken en draden).
# Draait los van de terminal (venster sluiten mag). Stoppen: sluit qpwgraph.

# ---- INSTELLINGEN ----------------------------------------------------------
VBAN_IP="192.168.1.2"     # IP van de andere computer met VBAN
VBAN_PORT="6980"          # standaard VBAN-poort
VBAN_IN_NAME="test-vban"  # streamnaam die we ONTVANGEN (max 16 tekens)
VBAN_OUT_NAME="test-vban" # streamnaam die we VERSTUREN (max 16 tekens)

# Opgeslagen opstelling (naast dit script). Bestaan ze, dan worden ze ingeladen:
#   jack_mixer: File -> Save As        -> mixer.xml       (kanalen en faders)
#   qpwgraph:   Patchbay -> Save As    -> mixer.qpwgraph  (draden)
MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIXER_FILE="$MAP/mixer.xml"
PATCHBAY_FILE="$MAP/mixer.qpwgraph"
# ----------------------------------------------------------------------------

set -u
pids=()

for c in pw-jack jack_mixer qpwgraph vban_receptor vban_emitter setsid; do
    command -v "$c" >/dev/null || { echo "FOUT: '$c' is niet geinstalleerd."; exit 1; }
done

# Loskoppelen van de terminal: anders stopt alles (zonder opslaan) zodra je
# het terminalvenster sluit. Meldingen gaan naar mixer.log.
LOG="$MAP/mixer.log"
if [ "${MIXER_LOSGEKOPPELD:-}" != 1 ]; then
    MIXER_LOSGEKOPPELD=1 setsid "$MAP/$(basename "${BASH_SOURCE[0]}")" "$@" \
        >"$LOG" 2>&1 </dev/null &
    echo "Mixer gestart. Je kunt deze terminal nu gerust sluiten."
    echo "Stoppen: sluit qpwgraph. Meldingen: $LOG"
    exit 0
fi

stop_alles() {
    echo "Stoppen..."
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
}
trap stop_alles EXIT INT TERM

# Oude onderdelen van een vorige start opruimen. Anders is VBAN-poort bezet
# ("unable to bind socket") en sluit een tweede qpwgraph meteen af, waarna
# dit script alles weer stopt.
oud_draait() {
    pgrep -u "$USER" -x qpwgraph >/dev/null ||
    pgrep -u "$USER" -x vban_receptor >/dev/null ||
    pgrep -u "$USER" -x vban_emitter >/dev/null ||
    pgrep -u "$USER" -f '(^|/)jack_mixer( |$)' >/dev/null
}
if oud_draait; then
    echo "Oude mixer-onderdelen draaien nog, die worden eerst gestopt..."
    pkill -u "$USER" -x qpwgraph
    pkill -u "$USER" -x vban_receptor
    pkill -u "$USER" -x vban_emitter
    pkill -u "$USER" -f '(^|/)jack_mixer( |$)'
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        oud_draait || break
        sleep 0.5
    done
    if oud_draait; then
        echo "FOUT: oude onderdelen willen niet stoppen:"
        pgrep -a -u "$USER" -f 'qpwgraph|vban_receptor|vban_emitter|jack_mixer'
        exit 1
    fi
fi

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
else
    echo "jack_mixer starten (leeg: $MIXER_FILE bestaat nog niet)..."
    pw-jack jack_mixer & pids+=($!)
fi

echo "VBAN ontvanger: $VBAN_IN_NAME van $VBAN_IP:$VBAN_PORT"
pw-jack vban_receptor -i "$VBAN_IP" -p "$VBAN_PORT" -s "$VBAN_IN_NAME" -b jack & pids+=($!)

# Let op: vban_emitter ondersteunt (nog) geen jack-backend; via pulseaudio
# verschijnt hij in PipeWire/qpwgraph toch als blok "vban" met ingangen FL/FR.
# De ontvanger-blok verschijnt pas zodra er echt VBAN-pakketten binnenkomen.
echo "VBAN zender: $VBAN_OUT_NAME naar $VBAN_IP:$VBAN_PORT"
# -r 48000: gelijk aan PipeWire (geen omrekenen). Vereist de aangepaste vban
# (pulseaudio_backend.c, kleine record-buffer), anders komt het geluid in stoten van ~2s.
vban_emitter -i "$VBAN_IP" -p "$VBAN_PORT" -s "$VBAN_OUT_NAME" -b pulseaudio -r 48000 -x 1024 & pids+=($!)

sleep 1
if [ -f "$PATCHBAY_FILE" ]; then
    # -a -x: patchbay actief + exclusief, dus qpwgraph legt de opgeslagen draden
    # terug en haalt automatische koppelingen weg (zoals vban -> USB-ingang).
    echo "qpwgraph openen met $PATCHBAY_FILE..."
    qpwgraph -a -x "$PATCHBAY_FILE"
else
    echo "qpwgraph openen (geen draden: $PATCHBAY_FILE bestaat nog niet)..."
    qpwgraph
fi
