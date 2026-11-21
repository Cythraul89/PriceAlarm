"""Generates assets/sounds/alarm.wav — an original alarm-clock style sound.

Synthesised here so the app ships no third-party audio (no licence question).
Pattern per loop: four short 2 kHz beeps, then a pause; the player loops it.
Run from src/:  python3 tool/generate_alarm_sound.py
"""
import math
import struct
import wave

RATE = 44100
FREQ = 2000.0          # typical alarm-clock pitch, clearly audible
BEEP = 0.09            # seconds per beep
GAP = 0.06             # seconds between beeps
PAUSE = 0.55           # seconds after the group of four
AMPLITUDE = 0.95       # of full scale
FADE = 0.004           # seconds; avoids clicks at beep edges


def beep(duration):
    n = int(RATE * duration)
    fade = int(RATE * FADE)
    for i in range(n):
        envelope = min(1.0, i / fade, (n - 1 - i) / fade)
        # Fundamental plus odd harmonics: a harsher, louder-sounding tone.
        t = i / RATE
        value = (math.sin(2 * math.pi * FREQ * t)
                 + 0.3 * math.sin(2 * math.pi * 3 * FREQ * t)
                 + 0.15 * math.sin(2 * math.pi * 5 * FREQ * t)) / 1.45
        yield AMPLITUDE * envelope * value


def silence(duration):
    return [0.0] * int(RATE * duration)


samples = []
for i in range(4):
    samples.extend(beep(BEEP))
    samples.extend(silence(GAP if i < 3 else PAUSE))

with wave.open('assets/sounds/alarm.wav', 'wb') as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(RATE)
    out.writeframes(b''.join(
        struct.pack('<h', int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
print(f'wrote assets/sounds/alarm.wav ({len(samples) / RATE:.2f} s)')
