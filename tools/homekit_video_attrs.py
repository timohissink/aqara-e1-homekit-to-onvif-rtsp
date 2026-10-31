#!/usr/bin/env python3
"""List the native video resolutions a HomeKit camera offers.

go2rtc never scales HomeKit video: it picks the LARGEST native resolution that
fits #maxwidth / #maxheight. Use this to choose values that give 16:9.

Input: a Home Assistant diagnostics download of the HomeKit Device config entry
(Settings > Devices & services > HomeKit Device > ... > Download diagnostics).
Usage: ./homekit_video_attrs.py diagnostics.json
"""
import base64, json, sys

SUPPORTED_VIDEO_CFG = "00000114-0000-1000-8000-0026BB765291"

def tlv(buf):
    i = 0
    while i + 2 <= len(buf):
        t, n = buf[i], buf[i + 1]
        yield t, buf[i + 2:i + 2 + n]
        i += 2 + n

def find_values(o):
    if isinstance(o, dict):
        if str(o.get("type", "")).upper() in (SUPPORTED_VIDEO_CFG, "114") and isinstance(o.get("value"), str):
            yield o["value"]
        for v in o.values():
            yield from find_values(v)
    elif isinstance(o, list):
        for v in o:
            yield from find_values(v)

data = json.load(open(sys.argv[1]))
for n, val in enumerate(find_values(data), 1):
    print(f"Video configuration #{n}:")
    for t, codec_cfg in tlv(base64.b64decode(val)):
        if t != 1:
            continue
        for t2, v2 in tlv(codec_cfg):
            if t2 == 3:  # video attributes
                a = dict(tlv(v2))
                w = int.from_bytes(a[1], "little"); h = int.from_bytes(a[2], "little"); fps = a[3][0]
                ratio = "16:9" if w * 9 == h * 16 else ("4:3" if w * 3 == h * 4 else f"{w}:{h}")
                print(f"  {w:>4}x{h:<4} @{fps}fps  {ratio}")
