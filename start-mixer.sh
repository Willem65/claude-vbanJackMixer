#!/usr/bin/env bash
# Start jack_mixer + VBAN ontvanger/zender + qpwgraph (patchbay met blokken en draden).
# Draait los van de terminal (venster sluiten mag).
# Stoppen: in qpwgraph Graph -> Quit (Ctrl+Q) (het kruisje verbergt hem alleen in het systeemvak).

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
    echo "Stoppen: in qpwgraph Graph -> Quit (Ctrl+Q). Meldingen: $LOG"
    exit 0
fi

jm_pid=""   # jack_mixer, alleen gezet als hij met mixer.xml is gestart

# jack_mixer stil laten opslaan naar mixer.xml (SIGUSR1 = Ctrl+S, zonder venster).
mixer_opslaan() {
    [ -n "$jm_pid" ] && kill -0 "$jm_pid" 2>/dev/null && kill -USR1 "$jm_pid"
}

stop_alles() {
    echo "Stoppen..."
    if mixer_opslaan; then
        echo "jack_mixer opgeslagen in $MIXER_FILE"
        sleep 1
    fi
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
}
trap stop_alles EXIT INT TERM

# Een vorige keer gestart script stoppen (niet zijn kinderen via de trap; die
# ruimen we hieronder zelf op). Het eigen proces en eigen subshells overslaan.
for p in $(pgrep -u "$USER" -f 'start-mixer\.sh'); do
    { [ "$p" = "$$" ] || [ "$p" = "$PPID" ]; } && continue
    [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$$" ] && continue
    kill -KILL "$p" 2>/dev/null
done

# Oude onderdelen van een vorige start opruimen, anders is de VBAN-poort bezet
# ("unable to bind socket"). qpwgraph blijft juist open: als je die geforceerd
# stopt, vergeet hij waar je de blokken hebt neergezet.
oud_draait() {
    pgrep -u "$USER" -x vban_receptor >/dev/null ||
    pgrep -u "$USER" -x vban_emitter >/dev/null ||
    pgrep -u "$USER" -f '(^|/)jack_mixer( |$)' >/dev/null
}
if oud_draait; then
    echo "Oude mixer-onderdelen draaien nog, die worden eerst gestopt..."
    # Een oude jack_mixer die met een bestand (-c) draait eerst laten opslaan.
    if pkill -USR1 -u "$USER" -f '(^|/)jack_mixer( .*)? -c '; then
        echo "Oude jack_mixer opgeslagen."
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
        echo "FOUT: oude onderdelen willen niet stoppen:"
        pgrep -a -u "$USER" -f 'vban_receptor|vban_emitter|jack_mixer'
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
    jm_pid=$!
    # jack_mixer slaat zichzelf op:
    #  - meteen zodra je in qpwgraph op Save drukt (mixer.qpwgraph verandert),
    #    zodat die ene Save-knop alles bewaart;
    #  - en voor de zekerheid elke 30 s.
    (
        laatst="$(stat -c %Y "$PATCHBAY_FILE" 2>/dev/null)"
        tel=0
        while sleep 2; do
            kill -0 "$jm_pid" 2>/dev/null || exit
            nu="$(stat -c %Y "$PATCHBAY_FILE" 2>/dev/null)"
            tel=$((tel + 2))
            if [ "$nu" != "$laatst" ] || [ "$tel" -ge 30 ]; then
                kill -USR1 "$jm_pid"
                laatst="$nu"
                tel=0
            fi
        done
    ) &
    pids+=($!)
else
    echo "jack_mixer starten (leeg: $MIXER_FILE bestaat nog niet)..."
    echo "Sla jack_mixer 1x op als $MIXER_FILE, daarna gaat opslaan automatisch."
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
# -a -x: patchbay actief + exclusief, dus qpwgraph legt de opgeslagen draden
# terug en haalt automatische koppelingen weg (zoals vban -> USB-ingang).
if [ -f "$PATCHBAY_FILE" ]; then
    qpw_args=(-a -x "$PATCHBAY_FILE")
else
    echo "Let op: $PATCHBAY_FILE bestaat nog niet (nog geen draden opgeslagen)."
    qpw_args=()
fi
if pgrep -u "$USER" -x qpwgraph >/dev/null; then
    # Draait al: dat venster gewoon houden (dan blijft je indeling van de
    # blokken bewaard). Een tweede qpwgraph geeft alles door aan de eerste.
    echo "qpwgraph draait al, die blijft open."
    qpwgraph "${qpw_args[@]}"
else
    echo "qpwgraph openen..."
    qpwgraph "${qpw_args[@]}" &
fi

# Wachten tot qpwgraph echt afgesloten is (Graph -> Quit, Ctrl+Q, of via het
# systeemvak-icoon -> Quit). Het venster met het kruisje sluiten verbergt
# qpwgraph alleen in het systeemvak; dan blijft de mixer gewoon draaien.
sleep 2
while pgrep -u "$USER" -x qpwgraph >/dev/null; do
    sleep 2
done
