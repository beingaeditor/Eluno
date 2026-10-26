"""Generate original, non-personal media for Eluno QA. Requires av, numpy, Pillow.

Optional --extra-site-packages points to an existing QA dependency directory.
Generated media stays in the ignored .eluno-local directory by default.
"""
import argparse
from fractions import Fraction
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--extra-site-packages')
parser.add_argument('--output', default='.eluno-local/fixtures')
args = parser.parse_args()
if args.extra_site_packages:
    sys.path.insert(0, str(Path(args.extra_site_packages).resolve()))

import av
import numpy as np
from PIL import Image, ImageDraw

out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)

def picture(index, width=640, height=360):
    image = Image.new('RGB', (width, height), '#17624c')
    draw = ImageDraw.Draw(image)
    draw.text((50, 70), 'ELUNO / GENERATED QA MEDIA', fill='#eee9cf')
    draw.text((50, 100), f'Frame {index:03d} - original sample', fill='#eee9cf')
    x = 65 + (index * 4) % 490
    draw.ellipse((x - 22, 215, x + 22, 259), fill='#d89f59')
    return image

still = picture(0)
still.save(out / 'eluno-photo.png')
still.save(out / 'eluno-photo.jpg', quality=90)
still.save(out / 'eluno-photo.webp', quality=90)

with av.open(str(out / 'eluno-h264-aac.mp4'), 'w', options={'movflags': '+faststart'}) as container:
    video = container.add_stream('libx264', rate=24)
    video.width, video.height, video.pix_fmt = 640, 360, 'yuv420p'
    video.options = {'preset': 'ultrafast', 'crf': '28', 'profile': 'baseline'}
    audio = container.add_stream('aac', rate=48000)
    audio.layout = 'mono'
    for index in range(120):
        frame = av.VideoFrame.from_image(picture(index))
        frame.pts, frame.time_base = index, Fraction(1, 24)
        for packet in video.encode(frame):
            container.mux(packet)
    for packet in video.encode():
        container.mux(packet)
    samples = 5 * 48000
    for start in range(0, samples, 1024):
        count = min(1024, samples - start)
        wave = (0.05 * np.sin(2 * np.pi * 440 * np.arange(start, start + count) / 48000)).astype('float32')[None, :]
        frame = av.AudioFrame.from_ndarray(wave, format='fltp', layout='mono')
        frame.sample_rate, frame.pts, frame.time_base = 48000, start, Fraction(1, 48000)
        for packet in audio.encode(frame):
            container.mux(packet)
    for packet in audio.encode():
        container.mux(packet)

with av.open(str(out / 'eluno-h264-aac.mp4')) as result:
    print({'durationSeconds': result.duration / av.time_base, 'codecs': [s.codec_context.name for s in result.streams], 'videoFramesDecoded': sum(1 for _ in result.decode(video=0))})
for path in sorted(out.iterdir()):
    print(f'{path.resolve()} ({path.stat().st_size} bytes)')
