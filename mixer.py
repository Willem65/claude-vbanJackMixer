#!/usr/bin/env python3
"""Hulpprogramma voor start-mixer.sh.

  mixer.py opslaan        faders (jack_mixer) + draden opslaan
  mixer.py bewaken        draden terugleggen zodra blokken (opnieuw) verschijnen
  mixer.py sluit-qpwgraph qpwgraph netjes sluiten (dan bewaart hij de plek van de blokken)
  mixer.py qpwgraph-instellen   qpwgraph als 'kijkvenster' instellen (vóór het starten)

De draden staan in mixer-verbindingen.txt: per regel "uitgang<TAB>ingang",
met de poortnamen zoals `pw-link -l` ze toont.
"""
import ctypes
import os
import re
import signal
import subprocess
import sys
import time

MAP = os.path.dirname(os.path.abspath(__file__))
VERBINDINGEN = os.path.join(MAP, "mixer-verbindingen.txt")
QPWGRAPH_CONF = os.path.expanduser("~/.config/rncbc.org/qpwgraph.conf")


# ---------------------------------------------------------------- PipeWire

def pw(*args):
    return subprocess.run(["pw-link", *args], capture_output=True, text=True).stdout


def huidige_verbindingen():
    links, poort = set(), None
    for regel in pw("-l").splitlines():
        if not regel.startswith(" "):
            poort = regel.strip()
        elif "|->" in regel and poort:
            links.add((poort, regel.split("|->", 1)[1].strip()))
    return links


def huidige_poorten():
    return {r.strip() for r in (pw("-o") + pw("-i")).splitlines() if r.strip()}


def lees_verbindingen():
    links = set()
    try:
        with open(VERBINDINGEN) as f:
            for regel in f:
                if "\t" in regel:
                    uit,_, inn = regel.rstrip("\n").partition("\t")
                    links.add((uit, inn))
    except FileNotFoundError:
        pass
    return links


# ---------------------------------------------------------------- opslaan

def jack_mixer_opslaan():
    """SIGUSR1 = jack_mixer slaat op naar het bestand waarmee hij gestart is (-c)."""
    r = subprocess.run(["pgrep", "-u", str(os.getuid()), "-f", r"(^|/)jack_mixer( .*)? -c "],
                       capture_output=True, text=True)
    pids = [int(p) for p in r.stdout.split()]
    for p in pids:
        os.kill(p, signal.SIGUSR1)
    return bool(pids)


def draden_opslaan():
    links = huidige_verbindingen()
    tmp = VERBINDINGEN + ".tmp"
    with open(tmp, "w") as f:
        for uit, inn in sorted(links):
            f.write(f"{uit}\t{inn}\n")
    os.replace(tmp, VERBINDINGEN)
    return len(links)


def opslaan():
    mixer = jack_mixer_opslaan()
    n = draden_opslaan()
    print(f"Opgeslagen: {n} draden" + (", jack_mixer" if mixer else " (jack_mixer draait niet)"))


# ---------------------------------------------------------------- bewaken

def bewaken():
    """Legt opgeslagen draden terug zodra een blok verschijnt, en haalt dan
    ook automatische koppelingen van PipeWire weg op poorten die in de
    opgeslagen lijst staan. Draden die je daarna zelf trekt of weghaalt,
    blijven met rust gelaten (alleen 'verse' poorten worden aangepast)."""
    VERS = 5          # seconden dat een nieuwe poort 'vers' blijft
    bekend, vers = set(), {}
    mtime, opgeslagen = None, set()
    while True:
        try:
            m = os.path.getmtime(VERBINDINGEN)
        except FileNotFoundError:
            m = None
        if m != mtime:
            mtime, opgeslagen = m, lees_verbindingen()
        opgeslagen_poorten = {p for link in opgeslagen for p in link}

        poorten = huidige_poorten()
        for p in poorten - bekend:
            vers[p] = VERS
        bekend = poorten

        if vers:
            links = huidige_verbindingen()
            for uit, inn in opgeslagen - links:
                if uit in poorten and inn in poorten and (vers.get(uit) or vers.get(inn)):
                    pw(uit, inn)
            for uit, inn in links - opgeslagen:
                if (uit in opgeslagen_poorten and vers.get(uit)) or \
                   (inn in opgeslagen_poorten and vers.get(inn)):
                    pw("-d", uit, inn)
            vers = {p: n - 1 for p, n in vers.items() if n > 1 and p in poorten}
        time.sleep(1)


# ---------------------------------------------------------------- qpwgraph

def qpwgraph_vensters():
    try:
        lijst = subprocess.run(["xprop", "-root", "_NET_CLIENT_LIST"],
                               capture_output=True, text=True).stdout
    except FileNotFoundError:
        return []
    ids = re.findall(r"0x[0-9a-fA-F]+", lijst)
    gevonden = []
    for w in ids:
        c = subprocess.run(["xprop", "-id", w, "WM_CLASS"], capture_output=True, text=True).stdout
        if '"qpwgraph"' in c:
            gevonden.append(int(w, 16))
    return gevonden


class _ClientMessage(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong),
                ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
                ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                ("format", ctypes.c_int), ("data", ctypes.c_long * 5)]


class _XEvent(ctypes.Union):
    _fields_ = [("xclient", _ClientMessage), ("pad", ctypes.c_long * 24)]


def venster_sluiten(venster):
    """Vraagt de window manager het venster netjes te sluiten (zoals het kruisje)."""
    x = ctypes.cdll.LoadLibrary("libX11.so.6")
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x.XInternAtom.restype = ctypes.c_ulong
    x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                             ctypes.c_long, ctypes.POINTER(_XEvent)]
    x.XFlush.argtypes = [ctypes.c_void_p]
    x.XCloseDisplay.argtypes = [ctypes.c_void_p]

    dpy = x.XOpenDisplay(None)
    if not dpy:
        return False
    ev = _XEvent()
    ev.xclient.type = 33                  # ClientMessage
    ev.xclient.send_event = 1
    ev.xclient.display = dpy
    ev.xclient.window = venster
    ev.xclient.message_type = x.XInternAtom(dpy, b"_NET_CLOSE_WINDOW", 0)
    ev.xclient.format = 32
    ev.xclient.data[0] = 0                # tijdstip
    ev.xclient.data[1] = 2                # bron: 'pager' (gebruiker)
    mask = (1 << 19) | (1 << 20)          # SubstructureNotify | SubstructureRedirect
    x.XSendEvent(dpy, x.XDefaultRootWindow(dpy), 0, mask, ctypes.byref(ev))
    x.XFlush(dpy)
    x.XCloseDisplay(dpy)
    return True


def qpwgraph_draait():
    return subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "qpwgraph"],
                          capture_output=True).returncode == 0


def sluit_qpwgraph(wacht=10):
    if not qpwgraph_draait():
        return 0
    vensters = qpwgraph_vensters()
    for v in vensters:
        venster_sluiten(v)
    eind = time.time() + wacht
    while time.time() < eind:
        if not qpwgraph_draait():
            return 0
        time.sleep(0.2)
    print("qpwgraph sluit niet (staat er een vraag open, of zit hij in het systeemvak?)",
          file=sys.stderr)
    return 1


def qpwgraph_instellen():
    """qpwgraph alleen nog als kijkvenster: de draden doet mixer.py zelf.
    Patchbay uit (geen 'opslaan?'-vragen meer) en geen systeemvak-icoon
    (anders sluit het kruisje qpwgraph niet echt af)."""
    gewenst = {"Patchbay": {"Activated": "false", "Exclusive": "false", "AutoPin": "false"},
               "SystemTray": {"Enabled": "false"}}
    try:
        regels = open(QPWGRAPH_CONF).read().splitlines()
    except FileNotFoundError:
        regels = []
    uit, sectie, gedaan = [], None, set()

    def rest_van(s):
        return [f"{k}={v}" for k, v in gewenst.get(s, {}).items() if (s, k) not in gedaan]

    for regel in regels:
        m = re.match(r"^\[(.+)\]$", regel)
        if m:
            uit.extend(rest_van(sectie))
            sectie = m.group(1)
            gedaan |= {(sectie, "__gezien__")}
        else:
            k = regel.split("=", 1)[0]
            if sectie in gewenst and k in gewenst[sectie]:
                if (sectie, k) in gedaan:
                    continue                      # dubbele regel weglaten
                regel = f"{k}={gewenst[sectie][k]}"
                gedaan.add((sectie, k))
        uit.append(regel)
    uit.extend(rest_van(sectie))
    for s, kv in gewenst.items():
        if (s, "__gezien__") not in gedaan:
            uit.append(f"[{s}]")
            uit.extend(f"{k}={v}" for k, v in kv.items())
    os.makedirs(os.path.dirname(QPWGRAPH_CONF), exist_ok=True)
    with open(QPWGRAPH_CONF, "w") as f:
        f.write("\n".join(uit) + "\n")


# ----------------------------------------------------------------

if __name__ == "__main__":
    opdracht = sys.argv[1] if len(sys.argv) > 1 else ""
    if opdracht == "opslaan":
        opslaan()
    elif opdracht == "bewaken":
        bewaken()
    elif opdracht == "sluit-qpwgraph":
        sys.exit(sluit_qpwgraph())
    elif opdracht == "qpwgraph-instellen":
        qpwgraph_instellen()
    else:
        print(__doc__)
        sys.exit(2)
