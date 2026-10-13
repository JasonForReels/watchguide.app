# Builds the soundtrack for update.html: each line in ../video-raw/vo/<name>.caf is placed at the
# start time listed in update.html's window.VO, over the music bed (../video-raw/score.wav, made by
# score.swift), which ducks while Simone speaks. The mix is then peak-normalized.
# Usage: python3 mix.py <out.m4a>
import array, json, os, re, subprocess, sys, tempfile, wave

HERE = os.path.dirname(os.path.abspath(__file__))
VO_DIR = os.path.join(HERE, "..", "video-raw", "vo")
RATE = 48000

html = open(os.path.join(HERE, "update.html")).read()
cues = json.loads(re.search(r"window\.VO = (\[.*?\]);", html).group(1))
total = float(re.search(r"const TOTAL = ([\d.]+);", html).group(1))

MUSIC = os.path.join(HERE, "..", "video-raw", "score.wav")
MUSIC_GAIN, DUCK_GAIN = 0.42, 0.21   # bed level between lines, and under the voice
mix = array.array("f", [0.0]) * int(total * RATE)
spans = []
with tempfile.TemporaryDirectory() as tmp:
    for name, start in cues:
        wav = os.path.join(tmp, name + ".wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1",
                        os.path.join(VO_DIR, name + ".caf"), wav], check=True)
        with wave.open(wav) as w:
            pcm = array.array("h", w.readframes(w.getnframes()))
        offset = int(start * RATE)
        end = min(len(mix), offset + len(pcm))
        if offset + len(pcm) > len(mix):
            print(f"warning: {name} runs past the end by {(offset + len(pcm) - len(mix)) / RATE:.2f}s")
        for i in range(offset, end):
            mix[i] += pcm[i - offset] / 32768.0
        spans.append((start, (offset + len(pcm)) / RATE))
        print(f"{name}: {start:5.2f}s → {(offset + len(pcm)) / RATE:5.2f}s")

    # Voice to about -1 dBFS on its own, then the music under it, ducked with soft edges.
    vgain = 0.89 / (max(abs(x) for x in mix) or 1.0)
    def duck(t):
        d = 0.0
        for a, b in spans:
            if a - 0.3 <= t <= b + 0.6:
                d = max(d, min(1.0, (t - (a - 0.3)) / 0.3, (b + 0.6 - t) / 0.6))
        return MUSIC_GAIN + (DUCK_GAIN - MUSIC_GAIN) * d
    with wave.open(MUSIC) as w:
        music = array.array("h", w.readframes(w.getnframes()))
    out = array.array("f", [0.0]) * (len(mix) * 2)
    for i, v in enumerate(mix):
        g = duck(i / RATE) if i % 480 == 0 else g
        for c in (0, 1):
            m = music[i * 2 + c] / 32768.0 if i * 2 + c < len(music) else 0.0
            out[i * 2 + c] = v * vgain + m * g
    peak = max(abs(x) for x in out) or 1.0
    norm = min(1.0, 0.95 / peak)
    stereo = array.array("h", (int(max(-1.0, min(1.0, x * norm)) * 32767) for x in out))
    wav = os.path.join(tmp, "mix.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(stereo.tobytes())
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", wav, sys.argv[1]], check=True)
print("wrote", sys.argv[1])
