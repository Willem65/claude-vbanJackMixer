#!/usr/bin/env bash
# Start jack_mixer + VBAN ontvanger/zender + qpwgraph (patchbay met blokken en draden).
# Pas hieronder de instellingen aan. Stoppen: sluit qpwgraph of druk Ctrl+C.

# ---- INSTELLINGEN ----------------------------------------------------------
VBAN_IP="192.168.1.2"     # IP van de andere computer met VBAN
VBAN_PORT="6980"          # standaard VBAN-poort
VBAN_IN_NAME="test-vban"  # streamnaam die we ONTVANGEN (max 16 tekens)
VBAN_OUT_NAME="test-vban" # streamnaam die we VERSTUREN (max 16 tekens)
# ----------------------------------------------------------------------------

set -u
pids=()

stop_alles() {
    echo "Stoppen..."
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
}
trap stop_alles EXIT INT TERM

for c in pw-jack jack_mixer qpwgraph vban_receptor vban_emitter; do
    command -v "$c" >/dev/null || { echo "FOUT: '$c' is niet geinstalleerd."; exit 1; }
done

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

echo "jack_mixer starten..."
pw-jack jack_mixer & pids+=($!)

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
echo "qpwgraph openen..."
qpwgraph
