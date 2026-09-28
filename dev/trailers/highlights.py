"""Cut a short overall trailer (trailers/trailer.mp4) from the recorded reels.

The reels print "MARK <name> <seconds>" into trailers/<reel>.log (TrailerDirector.mark); the
shots below are picked by those names, each fades in and out, then everything is concatenated.

    python dev/trailers/highlights.py [path/to/ffmpeg]
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'trailers')

# (reel, mark, offset after the mark, length) - None as mark = from the start of the reel
SHOTS = [
    ('heroes', None, 0.6, 3.4),               # "Heroes" title over the arena
    ('heroes', 'ability_tomato', 0.1, 3.0),
    ('heroes', 'ability_carrot', 0.1, 2.6),
    ('heroes', 'ability_pumpkin', 0.1, 2.8),
    ('heroes', 'ability_pepper', 0.1, 3.0),
    ('heroes', 'ability_pineapple', 0.1, 3.0),
    ('heroes', 'ability_banana', 0.1, 2.8),
    ('weapons', 'weapon_shotgun', 0.8, 2.4),
    ('weapons', 'weapon_rifle', 0.8, 2.6),
    ('weapons', 'weapon_flamethrower', 0.8, 2.8),
    ('loot', 'container_chest', 0.6, 3.2),
    ('loot', 'supply_drop', 2.4, 4.4),
    ('zone', 'zone_burn', 0.4, 3.4),
    ('zone', 'zone_rise', 0.2, 3.4),
    ('zone', 'zone_aerial', 1.0, 4.2),
    ('zone', 'zone_core', 0.6, 3.6),
    ('events', 'ev_meteors', 2.4, 3.6),       # red circles, the rocks come down
    ('events', 'ev_quake', 1.0, 3.2),
    ('events', 'ev_night', 3.0, 2.8),
    ('events', 'ev_rift', 5.0, 4.0),          # the crack burns, the ridge rises
    ('events', 'ev_harvest', 2.6, 3.4),
    ('events', 'ev_zone_drop', 3.5, 4.0),     # the rich drop lands and opens
    ('heroes', 'lineup', 1.0, 4.6),           # everyone, "Pick yours"
]
FADE = 0.18


def marks(reel):
    found = {}
    path = os.path.join(OUT, reel + '.log')
    if os.path.exists(path):
        for line in open(path, encoding='utf-8', errors='replace'):
            m = re.match(r'MARK (\S+) ([0-9.]+)', line.strip())
            if m:
                found[m.group(1)] = float(m.group(2))
    return found


def find_ffmpeg():
    if len(sys.argv) > 1:
        return sys.argv[1]
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return 'ffmpeg'


def main():
    ffmpeg = find_ffmpeg()
    cache = {}
    inputs, filters, labels = [], [], []
    for reel, mark, offset, length in SHOTS:
        video = os.path.join(OUT, reel + '.mp4')
        if not os.path.exists(video):
            print('skip (no video):', reel)
            continue
        cache.setdefault(reel, marks(reel))
        if mark is None:
            start = offset
        elif mark in cache[reel]:
            start = cache[reel][mark] + offset
        else:
            print('skip (no mark %s in %s.log)' % (mark, reel))
            continue
        i = len(labels)  # ffmpeg input index
        inputs += ['-ss', '%.3f' % start, '-t', '%.3f' % length, '-i', video]
        filters.append('[%d:v]setpts=PTS-STARTPTS,fade=t=in:st=0:d=%.2f,fade=t=out:st=%.3f:d=%.2f[v%d]'
                       % (i, FADE, length - FADE, FADE, i))
        labels.append('[v%d]' % i)
    if not labels:
        print('nothing to cut')
        return 1
    graph = ';'.join(filters) + ';' + ''.join(labels) + 'concat=n=%d:v=1:a=0[out]' % len(labels)
    cmd = [ffmpeg, '-y', '-loglevel', 'error'] + inputs + ['-filter_complex', graph, '-map', '[out]',
           '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
           os.path.join(OUT, 'trailer.mp4')]
    subprocess.run(cmd, check=True)
    print('-> trailers/trailer.mp4 (%d shots)' % len(labels))
    return 0


if __name__ == '__main__':
    sys.exit(main())
