# Visuele audiomixer op Ubuntu: jack\_mixer, qpwgraph en VBAN

Nov 17, 2026 · @Willem

## Doel en resultaat

Het geluid van Firefox loopt nu via een fader in jack\_mixer naar de eigen USB-geluidskaart en tegelijk via VBAN naar de Windows-pc (Voicemeeter), zonder haperingen. Dit document beschrijft hoe de opstelling op 17 november 2026 is gebouwd, welke problemen we tegenkwamen en hoe die zijn opgelost.

- **Doel:** een visuele mixer met blokken en pijlen (bronnen, mixer, geluidskaart, netwerk), te koppelen met VBAN.
- **Gebruikte tools:** PipeWire (standaard op Ubuntu 24.04), jack\_mixer (faders), qpwgraph (canvas met blokken en draden), VBAN (audio over het netwerk).
- **Status:** werkt. Lange-termijnwens: een eigen canvas bouwen (bijvoorbeeld Rust/axum met een webpagina).

## Overzicht van de opstelling

&#91;embedded content: signaalpad · Linux-pc naar Windows-pc via VBAN\]

Eén fader in jack\_mixer regelt het Firefox-geluid voor de eigen luidsprekers en voor de VBAN-stream naar Voicemeeter op de Windows-pc.

## Installatie

Alles staat erop: de pakketten via apt, en VBAN zelf gebouwd in `~/claude-axum/vban` en geïnstalleerd in `~/.local/bin`.

1. Pakketten installeren, in een **eigen terminalvenster** (Ctrl+Alt+T):

```bash
sudo apt update
sudo apt install -y pipewire-jack jack-mixer qpwgraph autoconf automake libtool pkg-config libjack-jackd2-dev
```

2. Bij de vraag *Enable realtime process priority?* kies **Yes**. Daarna eenmalig, en dan uit- en weer inloggen:

```bash
sudo usermod -aG audio willem
```

3. VBAN downloaden, bouwen en installeren (geen sudo nodig):

```bash
cd ~/claude-axum
git clone --depth 1 https://github.com/quiniouben/vban
cd vban && ./autogen.sh && ./configure --prefix=$HOME/.local && make && make install
```

**Valkuilen die we tegenkwamen:**

- `sudo` werkt niet vanuit de Claude-chat (ook niet met `!` ervoor): er is geen terminal om het wachtwoord in te typen. Gebruik altijd een eigen terminalvenster.
- Zet **nooit een `!`** voor een commando in een gewone terminal. In bash betekent `!` dat de uitkomst wordt omgekeerd; daardoor werd `apt install` stilletjes overgeslagen.
- Controleren of iets geïnstalleerd is: `command -v qpwgraph jack_mixer vban_emitter`.

## Startscript start-mixer.sh

Eén commando start alles: `cd ~/claude-axum && ./start-mixer.sh`. Draaien er nog VBAN-programma's, stop die eerst met `pkill vban_`, anders lopen er twee zenders tegelijk.

Het script start jack\_mixer, de VBAN-ontvanger, de VBAN-zender en daarna qpwgraph. Sluit je qpwgraph of druk je Ctrl+C, dan stopt alles. Pas bij een ander adres alleen de instellingen bovenaan aan:

| Instelling | Waarde | Betekenis |
| --- | --- | --- |
| `VBAN_IP` | 192.168.1.2 | IP-adres van de Windows-pc |
| `VBAN_PORT` | 6980 | Standaardpoort van VBAN |
| `VBAN_IN_NAME` | test-vban | Streamnaam die we ontvangen (max 16 tekens) |
| `VBAN_OUT_NAME` | test-vban | Streamnaam die we versturen (max 16 tekens) |

De twee VBAN-regels in het script:

```bash
pw-jack vban_receptor -i "$VBAN_IP" -p "$VBAN_PORT" -s "$VBAN_IN_NAME" -b jack
vban_emitter -i "$VBAN_IP" -p "$VBAN_PORT" -s "$VBAN_OUT_NAME" -b pulseaudio -r 48000 -x 1024
```

- De **zender** gebruikt `-b pulseaudio`, omdat vban\_emitter geen JACK ondersteunt (*"jack backend is not ready for emitter yet"*). In qpwgraph heet het blok **vban** (ingangen `input_FL` / `input_FR`).
- De **ontvanger** verschijnt pas als blok zodra er echt VBAN-pakketten binnenkomen.

## Werken met qpwgraph en jack\_mixer

Een fader zet je tussen een bron en de geluidskaart door de bron eerst naar een kanaal in jack\_mixer te leiden. In qpwgraph sleep je daarvoor een draad van een uitgang (rechts op een blok) naar een ingang (links op een ander blok).

**Een kanaal (fader) aanmaken in jack\_mixer**

1. Zoek het jack\_mixer-venster (Super-toets of Alt+Tab).
2. Kies *Mixer → Add Input Channel* (of Ctrl+N), geef een naam, vink **Stereo** aan en klik OK.
3. In qpwgraph krijgt het jack\_mixer-blok ingangen (`Input-1 L/R`) en uitgangen (`Input-1 Out L/R`).

**Huidige draden**

| Van (uitgang) | Naar (ingang) |
| --- | --- |
| Firefox `output_FL` / `output_FR` | jack\_mixer `Input-1 L` / `Input-1 R` |
| jack\_mixer `Input-1 Out L` / `R` | USB Audio Pro 2 `playback_AUX0` / `AUX1` |
| jack\_mixer `Input-1 Out L` / `R` | vban `input_FL` / `input_FR` |

Deze jack\_mixer heeft geen *MAIN*-uitgangen; gebruik daarom de uitgang van het kanaal zelf (`Input-N Out`).

**Wat de blokken in qpwgraph zijn**

- **USB Audio Pro / Pro 1 / Pro 2 / Pro 3:** onderdelen van één USB-geluidskaart (*capture* = ingang, *playback* = uitgang).
- **GA104 High Definition Audio:** de HDMI-uitgangen van de NVIDIA-videokaart.
- **vban \[record\]:** de VBAN-zender.

**Opstelling bewaren**

- [ ] In qpwgraph op **Save** klikken en **Activated** en **Exclusive** aanzetten. Dan legt qpwgraph de draden na een herstart zelf terug.
- [ ] In jack\_mixer de kanalen bewaren via *Mixer → Save*.

## VBAN naar Windows en het haperprobleem

Het haperen kwam door een fout in VBAN: de zender kreeg het geluid in blokken van ongeveer 2 seconden en stuurde die in één keer weg. Na een kleine aanpassing in de code en het overstappen op 48000 Hz loopt het geluid gelijkmatig.

**Instellingen in Voicemeeter (Windows, Incoming Stream)**

| Instelling | Waarde |
| --- | --- |
| Stream name | test-vban |
| IP-adres van de zender (Linux-pc) | 192.168.1.113 |
| Poort | 6980 |
| Formaat | 48000 Hz, 16 bit, 2 kanalen |
| Net Quality | Medium (probeer later Fast) |

Hoor je niets op Windows, controleer dan of de firewall daar **UDP-poort 6980** doorlaat.

**Wat er mis was**

- Bij opnemen gaf VBAN geen buffergrootte door aan PipeWire. PipeWire koos dan de standaard: blokken van 88200 samples, ongeveer 2 seconden. Windows kreeg daardoor stootjes in plaats van een gelijkmatige stroom. De optie `-x` hielp niet, want die wordt bij opnemen niet gebruikt.
- De zender verstuurde op 44100 Hz terwijl PipeWire op 48000 Hz werkt, dus alles werd onderweg omgerekend.

**De oplossing**

Twee regels aangepast in `vban/src/common/backend/pulseaudio_backend.c` (het origineel staat ernaast als `.orig`). Daarna opnieuw gebouwd met `make && make install`.

```c
/* record: kleine fragmenten i.p.v. ~2s standaard */
.fragsize = (direction == AUDIO_IN) ? buffer_size : (unsigned int)(-1)
/* en de buffer-instellingen nu ook bij opnemen meegeven: */
pa_simple_new(..., &ss, 0, &ba, &ret);
```

Resultaat: het vban-blok vraagt het geluid nu op in blokken van 256 samples (ongeveer 5 ms) op 48000 Hz. Let op: haal je VBAN opnieuw van GitHub, dan moet deze aanpassing er opnieuw in.

## Problemen en oplossingen

De meeste problemen kwamen door automatische verbindingen van PipeWire en door verwarring over waar een commando moet worden uitgevoerd.

| Probleem | Oorzaak | Oplossing |
| --- | --- | --- |
| Geen geluid meer op Windows na herstart van de zender | PipeWire koppelde het nieuwe vban-blok aan de USB-ingang (stilte) | Draad USB-ingang → vban weghalen; jack\_mixer `Input-1 Out` → vban verbinden. Voorkomen: qpwgraph Save + Activated + Exclusive |
| Geluid op Windows hapert | VBAN stuurde blokken van ongeveer 2 s; omrekenen 44100 → 48000 Hz | Aangepaste VBAN-code en `-r 48000` (zie VBAN-sectie) |
| Fader heeft geen effect | Firefox ging rechtstreeks naar de geluidskaart | Firefox → jack\_mixer `Input-1` → geluidskaart |
| jack\_mixer heeft geen ingangen | Nog geen kanaal aangemaakt | *Mixer → Add Input Channel* (Ctrl+N) |
| VBAN-ontvanger niet zichtbaar in qpwgraph | Er komen nog geen pakketten binnen | Verschijnt vanzelf zodra de andere kant verstuurt |
| `vban_emitter`: *jack backend is not ready* | Zender ondersteunt geen JACK | `-b pulseaudio` gebruiken |
| `apt install` deed niets | `!` voor het commando in een gewone terminal | Commando zonder `!` uitvoeren |
| *sudo: a terminal is required* | sudo via de Claude-chat | In een eigen terminalvenster uitvoeren |
| IP 123.456.7.8 werkt niet | Ongeldig adres (elk getal maximaal 255) | Een geldig adres gebruiken, bijvoorbeeld 192.168.1.123 |

Handige controlecommando's: `pw-link -l` (alle draden), `pw-top` (wat speelt er en met welke buffer), `pgrep -a vban_` (draaiende VBAN-programma's).

## Volgende stappen

De volgende stap is Teams toevoegen als eigen kanaal; daarna de eigen canvas.

- [ ] **Teams op deze Linux-pc:** via https://teams.microsoft.com in Google Chrome, of de app *Teams for Linux*. Teams verschijnt dan als blok in qpwgraph; geef het een eigen kanaal in jack\_mixer.
- [ ] **Virtuele microfoon voor Teams**, zodat de mixer als microfoon gekozen kan worden:

```bash
pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=mixer-mic channel_map=front-left,front-right
```

Kies in Teams *mixer-mic* als microfoon. Verbind de Teams-fader **niet** met mixer-mic, anders hoort de andere kant zichzelf terug.

- [ ] **Teams op Windows (alternatief):** in Voicemeeter een Outgoing Stream *teams* naar 192.168.1.113, en op Linux een tweede ontvanger: `pw-jack vban_receptor -i 192.168.1.2 -p 6980 -s teams -b jack`.
- [ ] **Eigen canvas:** een Rust/axum-server met een webpagina (bijvoorbeeld Drawflow of Rete.js) die de echte blokken toont, draden laat slepen en VBAN-zenders kan starten.

## Links

- [JACK-applicaties](https://jackaudio.org/applications/) en [jackaudio.org](https://jackaudio.org/)
- [jack\_mixer](https://github.com/jack-mixer/jack_mixer)
- [VBAN voor Linux (quiniouben)](https://github.com/quiniouben/vban) en [uitleg VBAN-protocol](https://vb-audio.com/Voicemeeter/vban.htm)
- [qpwgraph](https://gitlab.freedesktop.org/rncbc/qpwgraph), [Helvum (Rust)](https://gitlab.freedesktop.org/pipewire/helvum), [Carla](https://kx.studio/Applications:Carla), [RaySession](https://github.com/Houston4444/RaySession)
- Canvas-bibliotheken: [Drawflow](https://jerosoler.github.io/Drawflow/), [Rete.js](https://retejs.org/), [React Flow](https://reactflow.dev/examples)
- JACK vanuit code: [rust-jack](https://github.com/RustAudio/rust-jack), [JACK-Client voor Python](https://jackclient-python.readthedocs.io/)
- [Teams for Linux](https://github.com/IsmaelMartinez/teams-for-linux)
