#!/usr/bin/env python3
"""Text → 24 kHz wav with Kokoro. Usage: tts.py --out FILE [--voice NAME] [--speed 1.0] TEXT...
Model files live in ~/.brain/models. Prints the audio length in seconds; timing on stderr."""
import argparse, os, sys, time

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True); ap.add_argument('--voice', default=os.environ.get('KOKORO_VOICE', 'am_michael'))
    ap.add_argument('--speed', type=float, default=1.0); ap.add_argument('text', nargs='+'); a = ap.parse_args()
    import soundfile as sf
    from kokoro_onnx import Kokoro
    m = os.path.expanduser('~/.brain/models')
    k = Kokoro(os.path.join(m, 'kokoro-v1.0.onnx'), os.path.join(m, 'voices-v1.0.bin'))
    t = time.time(); audio, sr = k.create(' '.join(a.text), voice=a.voice, speed=a.speed, lang='en-us')
    sf.write(a.out, audio, sr); print(f'{len(audio)/sr:.2f}'); print(f'kokoro {a.voice}: {time.time()-t:.2f}s', file=sys.stderr)

if __name__ == '__main__': main()
