"""Builds the game's sound effects (audio/sfx/*.ogg) from FL Studio's factory sample packs.

    D:\\royaltim-ai\\venv\\Scripts\\python.exe tools/audio/make_sfx.py [--packs D:/flstud/Data/Patches/Packs]

Every sound below is one sample from the packs, cut to `cut` seconds with a short fade, given a
pitch (`rate`: 0.8 = lower, slower), brought to its own mean loudness (so a pistol and a
minigun round sit right next to each other) with the peaks limited, and made mono (they are played in
3D) Ogg Vorbis. Names are the ids effects/Sfx.gd plays. Rerun after changing the table; the .ogg
files are committed, the packs are not needed to build the game.
"""
import argparse
import os
import subprocess
import sys

try:
    import imageio_ffmpeg
    FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except ImportError:
    FFMPEG = "ffmpeg"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "audio", "sfx")

# id: (file in the packs, cut seconds, rate, mean loudness dB - peaks are limited to -1 dB)
SOUNDS = {
    # guns (RangedWeapon.WeaponType order)
    "gun_pistol": ("Drums (ModeAudio)/Snares/Attack Snare 03.wv", 0.35, 1.15, -16),
    "gun_shotgun": ("Drums/SFX/Smigen Boom SFX.wav", 0.7, 1.0, -13),
    "gun_sniper": ("Legacy/FX/FLS_Gun 001.wav", 0.7, 1.0, -14),
    "gun_rifle": ("Drums/Percussion/909 Clap.wav", 0.3, 1.1, -18),
    "gun_flame": ("Drums (ModeAudio)/Foley/MA Spray.wv", 0.5, 0.8, -22),
    "gun_smg": ("Drums (ModeAudio)/Rims/Fracture Rim 03.wv", 0.2, 1.2, -19),
    "gun_cannon": ("Legacy/FX/FLS_Gun 001.wav", 0.8, 0.75, -12),
    "gun_marksman": ("Drums (ModeAudio)/Snares/Attack Snare 12.wv", 0.45, 0.9, -15),
    "gun_minigun": ("Drums (ModeAudio)/Rims/Fracture Rim 07.wv", 0.15, 1.0, -20),
    "gun_double": ("SFX/SFX Chunk Thud.wav", 0.4, 0.9, -13),
    "gun_jam": ("Drums/SFX/Toidiling Lazer SFX.wav", 0.45, 1.0, -18),
    "gun_launcher": ("Drums (ModeAudio)/Foley/MA Tub Thud 01.wv", 0.4, 0.8, -16),
    # combat
    "explosion": ("SFX/SFX Crush Explode.wav", 0.8, 1.0, -12),
    "reload": ("Drums (ModeAudio)/Foley/MA Keys Grab 01.wv", 0.4, 1.0, -24),
    "reload_done": ("Drums (ModeAudio)/Foley/MA Lock Snap 01.wv", 0.3, 1.0, -24),
    "empty": ("Drums (ModeAudio)/Foley/MA Calculator Button 01.wv", 0.15, 0.9, -24),
    "hit": ("Drums/Percussion/FPC Wack.wav", 0.15, 1.3, -20),
    "hurt": ("Drums (ModeAudio)/Foley/MA Pillow Thud 01.wv", 0.3, 0.9, -18),
    "kill": ("Drums/Percussion/FPC Triangle.wav", 0.7, 1.3, -20),
    "death": ("Drums/SFX/Stomper OhNo SFX.wav", 1.2, 1.0, -18),
    # loot
    "chest_open": ("Drums (ModeAudio)/Foley/MA Lid Pop 03.wv", 0.35, 0.9, -20),
    "pickup": ("Drums (ModeAudio)/Foley/MA Keys Grab 02.wv", 0.35, 1.1, -22),
    "pickup_ammo": ("Drums (ModeAudio)/Foley/MA Staples Shake 01.wv", 0.35, 1.0, -22),
    "heal": ("Drums (ModeAudio)/Foley/MA WaterBottle Shake.wv", 0.8, 1.0, -24),
    "shield": ("Drums/Percussion/FPC Glass Bell.wav", 0.9, 1.0, -24),
    "supply_drop": ("Risers/Riser Noise Takeoff.wv", 2.5, 0.8, -22),
    "thud": ("Drums (ModeAudio)/Foley/MA Basket Thud 01.wv", 0.4, 0.8, -16),
    # abilities, weeds
    "ability": ("Drums/SFX/Stomper Swsh SFX.wav", 0.5, 1.0, -20),
    "weed_spit": ("Drums/SFX/Bracke Burp SFX.wav", 0.5, 1.2, -20),
    "weed_die": ("Drums/SFX/Toy Rip SFX.wav", 0.5, 1.0, -20),
    # the zone and the map events
    "zone_warn": ("Risers/Riser Storm.wv", 2.5, 1.0, -24),
    "rumble": ("SFX/SFX Earthquake.wav", 2.8, 1.0, -16),
    "meteor": ("SFX/SFX Lightning.wav", 1.6, 0.9, -17),
    "flood": ("SFX/SFX Splash Noiz.wav", 1.5, 0.8, -20),
    "night": ("SFX/FX Choir Swell.wav", 3.0, 1.0, -24),
    "harvest": ("Drums/Percussion/FPC Glass Bell.wav", 1.0, 1.2, -24),
    # interface
    "ui_click": ("Drums (ModeAudio)/Foley/MA JewelCase Click.wv", 0.15, 1.0, -26),
    "ui_hover": ("Drums (ModeAudio)/Foley/MA Glass Tap 01.wv", 0.12, 1.4, -34),
    "countdown": ("Drums/Percussion/FPC Wood Hit 2.wav", 0.3, 1.0, -22),
    "match_start": ("Drums/Cymbals/909 Crash.wav", 1.5, 1.0, -22),
    "match_found": ("Drums/Percussion/FPC Glass Bell.wav", 1.2, 0.9, -24),
    "victory": ("Legacy/FX/FLS_Applause 001.wav", 3.5, 1.0, -22),
    "defeat": ("SFX/FX Spin Down.wav", 2.0, 1.0, -22),
    "coins": ("Drums (ModeAudio)/Foley/MA Coins Drop 01.wv", 0.8, 1.0, -22),
    "purchase": ("Drums (ModeAudio)/Foley/MA Coins Clap.wv", 0.5, 1.0, -22),
}


def unwrap(path, tmp_dir):
    """FL Studio stores many factory .wav files as Ogg Vorbis inside a RIFF header (format 0x674F
    "Og"), which ffmpeg can't read: hand it the Ogg stream from the data chunk instead."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return path
    i = 12
    fmt_tag = None
    while i + 8 <= len(data):
        cid, size = data[i:i + 4], int.from_bytes(data[i + 4:i + 8], "little")
        body = data[i + 8:i + 8 + size]
        if cid == b"fmt ":
            fmt_tag = int.from_bytes(body[:2], "little")
        elif cid == b"data" and fmt_tag in (0x674F, 0x6750, 0x6751, 0x676F, 0x6770, 0x6771):
            out = os.path.join(tmp_dir, "unwrapped.ogg")
            with open(out, "wb") as f:
                f.write(body[body.find(b"OggS"):])
            return out
        i += 8 + size + (size & 1)
    return path


def build(packs, only=None):
    os.makedirs(OUT, exist_ok=True)
    for sid, (src, cut, rate, mean) in SOUNDS.items():
        if only and sid not in only:
            continue
        path = os.path.join(packs, src)
        if not os.path.exists(path):
            print("MISSING", sid, path)
            continue
        fade = min(0.08, cut * 0.3)
        # pitch by resampling (asetrate), cut, fade out, peak-normalise to `peak` dB, mono 44.1 kHz
        flt = ("asetrate=44100*{r},aresample=44100,atrim=0:{c},afade=t=out:st={fs}:d={f},"
               "silenceremove=start_periods=1:start_threshold=-55dB").format(r=rate, c=cut, fs=max(cut - fade, 0), f=fade)
        tmp = os.path.join(OUT, sid + ".tmp.wav")
        subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", unwrap(path, OUT), "-ac", "1", "-af", flt, tmp], check=True)
        probe = subprocess.run([FFMPEG, "-i", tmp, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True).stderr
        mean_db = float(probe.split("mean_volume:")[1].split("dB")[0]) if "mean_volume:" in probe else -20.0
        gain = "volume=%.2fdB,alimiter=limit=0.89:attack=1:release=30:level=disabled" % (mean - mean_db)
        subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", tmp, "-af", gain,
                        "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, sid + ".ogg")], check=True)
        os.remove(tmp)
        if os.path.exists(os.path.join(OUT, "unwrapped.ogg")):
            os.remove(os.path.join(OUT, "unwrapped.ogg"))
        print("%-14s %s" % (sid, src))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--packs", default="D:/flstud/Data/Patches/Packs")
    ap.add_argument("only", nargs="*")
    a = ap.parse_args()
    build(a.packs, set(a.only) or None)
