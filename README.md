# vban-jack-mixer

Visuele audiomixer op Linux (PipeWire) met **jack_mixer**, **qpwgraph** en
**VBAN**, om audio over het netwerk uit te wisselen met een Windows-pc met
Voicemeeter.

```
Firefox / apps ──► jack_mixer ──► USB-audio / HDMI
                       │
                       └──► vban_emitter ──► netwerk ──► Voicemeeter (Windows)
Voicemeeter ──► vban_receptor ──► jack_mixer ──► USB-audio
```

## Benodigd

Ubuntu 24.04 of vergelijkbaar, met PipeWire (48 kHz).

```bash
sudo apt install pipewire-jack jack-mixer qpwgraph \
    git build-essential autoconf automake \
    libasound2-dev libpulse-dev libjack-jackd2-dev
```

## VBAN bouwen (met patch)

De standaardversie van `vban_emitter` neemt via PulseAudio op in blokken van
~2 seconden, waardoor het geluid aan de andere kant in stoten aankomt.
De patch in `patches/` zet de opnamebuffer (`fragsize`) klein.

```bash
git clone https://github.com/quiniouben/vban
cd vban
git checkout v2.2.0
git apply ../patches/vban-pulseaudio-fragsize.patch
./autogen.sh
./configure --prefix="$HOME/.local"
make
make install
```

Zorg dat `~/.local/bin` in je `PATH` staat.

## Gebruik

Pas bovenaan `start-mixer.sh` het IP-adres, de poort en de streamnamen aan
en start:

```bash
./start-mixer.sh
```

Het script start jack_mixer, de VBAN-ontvanger en -zender en opent qpwgraph.
Daarin verbind je de blokken met draden.

### Drie knoppen

Kopieer de snelkoppelingen uit `menu/` naar `~/.local/share/applications/`
(pas daarin het pad aan). Dan staan in het app-menu:

| Knop | Wat het doet |
|---|---|
| **Mixer starten** | alles starten met de opgeslagen opstelling |
| **Mixer opslaan** | faders, draden en plek van de blokken opslaan |
| **Mixer stoppen** | alles opslaan en afsluiten |

qpwgraph met het kruisje sluiten werkt ook als stoppen (en slaat ook op).

### Waar wordt wat bewaard

| Wat | Bestand | Door |
|---|---|---|
| kanalen en faders | `mixer.xml` | jack_mixer (ook elke 30 s automatisch) |
| draden | `mixer-verbindingen.txt` | `mixer.py` |
| plek van de blokken | `~/.config/rncbc.org/qpwgraph.conf` | qpwgraph, bij afsluiten |

`mixer.py bewaken` legt de draden terug zodra een blok verschijnt (ook later,
bijvoorbeeld Firefox als het geluid gaat spelen) en haalt dan automatische
koppelingen van PipeWire weg. qpwgraph is alleen nog kijk- en tekenvenster:
het script zet zijn eigen patchbay en systeemvak-icoon uit.

## Valkuilen

- `vban_emitter` heeft geen jack-backend; hij draait via PulseAudio
  (`-b pulseaudio -r 48000`) en verschijnt in qpwgraph als blok **vban-zender**.
- Het blok **vban-ontvanger** verschijnt pas als er echt VBAN-pakketten binnenkomen.
- jack_mixer heeft hier geen MAIN-uitgangen; gebruik de uitgangen
  `Input-N Out` van de kanalen.
- Na een herstart koppelt PipeWire `vban_emitter` soms automatisch aan de
  USB-ingang (stilte). Opnieuw bedraden, of in qpwgraph de patchbay opslaan
  en *Activated* + *Exclusive* aanzetten.
- Firefox verschijnt pas als blok zodra het geluid afspeelt.

## Licentie

`start-mixer.sh` en de documentatie: eigen werk.
De patch in `patches/` is een wijziging op
[quiniouben/vban](https://github.com/quiniouben/vban) en valt onder de
GPL-3.0-licentie van dat project.
