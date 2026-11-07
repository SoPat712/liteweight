#!/usr/bin/env python3
"""Generate liteweight's original interaction sounds. Run on macOS with afconvert.

Only the Python standard library is used. WAV intermediates are temporary;
the reproducible, uncompressed CAFs are the app/notification bundle resources.
"""

from array import array
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import wave


SAMPLE_RATE = 44100
OUTPUT = Path(__file__).resolve().parents[1] / "liteweight/Resources/Sounds"


def silence(duration):
    return array("d", [0.0]) * round(duration * SAMPLE_RATE)


def envelope(time, duration, decay, attack=0.003):
    fade_in = 0.5 - 0.5 * math.cos(math.pi * min(time / attack, 1.0))
    fade_out = 0.5 - 0.5 * math.cos(
        math.pi * min(max((duration - time) / 0.012, 0.0), 1.0)
    )
    return fade_in * math.exp(-time / decay) * fade_out


def note(buffer, start, duration, frequency, decay, gain=1.0, bell=False,
         shimmer=False, attack=0.003):
    # Quiet, slightly inharmonic upper modes decay faster than the warm body.
    partials = ((1.0, 1.0), (2.015, 0.18), (3.97, 0.045)) if bell else (
        (1.0, 1.0), (2.76, 0.13), (4.03, 0.025)
    )
    offset = round(start * SAMPLE_RATE)
    for index in range(min(round(duration * SAMPLE_RATE), len(buffer) - offset)):
        time = index / SAMPLE_RATE
        value = sum(
            amplitude * math.exp(-time * (ratio - 1.0) / (decay * 1.7))
            * math.sin(math.tau * frequency * ratio * time)
            for ratio, amplitude in partials
        )
        if shimmer:
            value += 0.025 * math.sin(math.tau * frequency * 2.006 * time) * (
                0.5 + 0.5 * math.sin(math.tau * 5.0 * time)
            )
        buffer[offset + index] += gain * value * envelope(
            time, duration, decay, attack
        )


def low_pass(buffer, cutoff):
    coefficient = 1.0 - math.exp(-math.tau * cutoff / SAMPLE_RATE)
    first = second = 0.0
    for index, value in enumerate(buffer):
        first += coefficient * (value - first)
        second += coefficient * (first - second)
        buffer[index] = second


def sounds():
    complete = silence(0.180)
    note(complete, 0.0, 0.14, 783.991, 0.035, gain=0.85)
    note(complete, 0.075, 0.105, 1174.659, 0.030, gain=0.70)

    record = silence(0.600)
    for start, frequency, duration, decay in (
        (0.0, 1046.502, 0.34, 0.080),
        (0.095, 1318.510, 0.37, 0.100),
        (0.190, 1567.982, 0.41, 0.130),
    ):
        note(record, start, duration, frequency, decay, bell=True, shimmer=True)

    tick = silence(0.020)
    seed = 7
    noise = 0.0
    for index in range(len(tick)):
        time = index / SAMPLE_RATE
        seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF
        noise += 0.22 * ((seed / 2147483648.0 - 1.0) - noise)
        tick[index] = (0.65 * math.sin(math.tau * 360 * time) + 0.45 * noise) * (
            envelope(time, 0.020, 0.004, attack=0.0025)
        )

    rest = silence(0.900)
    note(rest, 0.0, 0.52, 1318.510, 0.130, gain=0.85, bell=True)
    note(rest, 0.29, 0.61, 1046.502, 0.180, bell=True)

    finish = silence(1.200)
    for start, frequency in ((0.0, 523.251), (0.06, 659.255),
                             (0.12, 783.991), (0.18, 1046.502)):
        note(finish, start, 1.2 - start, frequency, 0.30, gain=0.65,
             bell=True, shimmer=True, attack=0.005)

    return (
        ("set_complete", complete, -6.0, 4800),
        ("set_record", record, -5.0, 6000),
        ("tick", tick, -12.0, 2200),
        ("rest_complete", rest, -6.0, 4800),
        ("workout_finish", finish, -6.0, 5200),
    )


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="liteweight-sounds-") as temporary:
        for name, buffer, peak_db, cutoff in sounds():
            low_pass(buffer, cutoff)
            # Bring the filter tail smoothly to zero, then normalize with headroom.
            fade_samples = min(round(0.005 * SAMPLE_RATE), len(buffer))
            for index in range(fade_samples):
                buffer[-fade_samples + index] *= 0.5 + 0.5 * math.cos(
                    math.pi * index / (fade_samples - 1)
                )
            gain = 10 ** (peak_db / 20.0) / max(abs(value) for value in buffer)
            pcm = [round(value * gain * 32767) for value in buffer]
            assert max(abs(value) for value in pcm) <= 23197  # <= -3 dBFS
            assert pcm[0] == pcm[-1] == 0
            wav_path = Path(temporary) / (name + ".wav")
            with wave.open(str(wav_path), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(SAMPLE_RATE)
                output.writeframes(struct.pack("<" + "h" * len(pcm), *pcm))
            subprocess.run(
                ["/usr/bin/afconvert", "-f", "caff", "-d", "LEI16@44100",
                 str(wav_path), str(OUTPUT / (name + ".caf"))], check=True
            )
            measured_peak = 20 * math.log10(max(abs(value) for value in pcm) / 32768)
            print(f"{name:18s} {len(pcm) / SAMPLE_RATE:.3f} s  "
                  f"{measured_peak:.2f} dBFS  44100 Hz mono 16-bit PCM")


if __name__ == "__main__":
    main()
