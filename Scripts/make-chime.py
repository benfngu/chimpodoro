"""Generate Chimpodoro's original, short completion chime (standard library only)."""
import math
from pathlib import Path
import struct
import wave

rate = 22050
length = 1.65
notes = [(0.0, 523.251), (0.23, 659.255), (0.46, 783.991)]
samples = []
for i in range(round(rate * length)):
    t = i / rate
    value = 0.0
    for start, frequency in notes:
        age = t - start
        if age < 0:
            continue
        attack = min(age / 0.012, 1.0)
        release = min((length - t) / 0.12, 1.0)
        tone = math.sin(2 * math.pi * frequency * age)
        tone += 0.18 * math.sin(2 * math.pi * frequency * 2 * age) * math.exp(-age * 7)
        value += 0.28 * attack * release * math.exp(-age * 3.7) * tone
    samples.append(round(max(-1, min(1, value)) * 32767))
path = Path(__file__).resolve().parents[1] / 'Assets' / 'Completion.wav'
with wave.open(str(path), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(struct.pack(f'<{len(samples)}h', *samples))
print(path)
