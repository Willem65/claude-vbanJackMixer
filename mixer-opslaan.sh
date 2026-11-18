#!/usr/bin/env bash
# Knop "Mixer opslaan": faders, draden en de plek van de blokken bewaren.
# qpwgraph bewaart de plek van de blokken alleen bij afsluiten; daarom wordt
# qpwgraph even gesloten en door start-mixer.sh meteen weer geopend.
MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

melding() { echo "$1"; notify-send -i document-save "Mixer" "$1" 2>/dev/null; }

uitvoer="$(python3 "$MAP/mixer.py" opslaan 2>&1)"

if pgrep -u "$USER" -x qpwgraph >/dev/null; then
    if pgrep -u "$USER" -f 'start-mixer\.sh' >/dev/null; then
        touch "$MAP/.qpwgraph-herstart"
        if python3 "$MAP/mixer.py" sluit-qpwgraph; then
            melding "Opgeslagen: faders, draden en plek van de blokken. ($uitvoer)"
        else
            rm -f "$MAP/.qpwgraph-herstart"
            melding "Faders en draden opgeslagen, maar qpwgraph wilde niet sluiten (staat er een vraag open?). Plek van de blokken niet bewaard."
        fi
    else
        melding "Faders en draden opgeslagen. (Mixer is niet via 'Mixer starten' gestart; plek van de blokken bewaart qpwgraph bij afsluiten.)"
    fi
else
    melding "Opgeslagen. ($uitvoer)"
fi
