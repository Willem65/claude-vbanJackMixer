#!/usr/bin/env bash
# Knop "Mixer stoppen": eerst alles opslaan, dan alles netjes afsluiten.
MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

melding() { echo "$1"; notify-send -i media-playback-stop "Mixer" "$1" 2>/dev/null; }

python3 "$MAP/mixer.py" opslaan
rm -f "$MAP/.qpwgraph-herstart"

# qpwgraph netjes sluiten (bewaart plek van de blokken). start-mixer.sh ziet
# dat en stopt de rest (en slaat daarbij nogmaals op).
if ! python3 "$MAP/mixer.py" sluit-qpwgraph; then
    melding "qpwgraph wilde niet sluiten (staat er een vraag open?). Niets gestopt."
    exit 1
fi

# Wachten tot start-mixer.sh alles gestopt heeft.
for _ in $(seq 1 20); do
    pgrep -u "$USER" -x vban_receptor >/dev/null ||
    pgrep -u "$USER" -x vban_emitter >/dev/null ||
    pgrep -u "$USER" -f '(^|/)jack_mixer( |$)' >/dev/null || { melding "Mixer opgeslagen en gestopt."; exit 0; }
    sleep 0.5
done

# start-mixer.sh draaide kennelijk niet: zelf opruimen (jack_mixer is al opgeslagen).
pkill -u "$USER" -x vban_receptor
pkill -u "$USER" -x vban_emitter
pkill -u "$USER" -f '(^|/)jack_mixer( |$)'
pkill -u "$USER" -f 'mixer\.py bewaken'
melding "Mixer opgeslagen en gestopt."
