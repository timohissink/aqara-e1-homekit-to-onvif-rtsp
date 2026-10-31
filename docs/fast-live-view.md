# Fast Apple Home live view and clean snapshots

Out of the box, Apple Home live view of an E1 re-exported through Scrypted can
take **3–7 seconds** to start, and the still image ("snapshot") on the camera
tile can look grey, smeared or outdated. Both problems have the same root
cause, and both can be fixed on the Home Assistant side.

## Why it is slow

- The Aqara E1 sends a keyframe (IDR) only every **~6.7 s** (GOP ≈ 100 frames
  at 15 fps). This cannot be changed on the camera.
- A decoder (Apple Home, ffmpeg, ...) can only show a picture from a keyframe
  onwards.
- Scrypted's Rebroadcast plugin keeps a prebuffer and sends the stream from
  the latest keyframe in it. But it only looks back
  `min(2 s remote / 4 s local, detected keyframe interval)`. With a 6.7 s GOP
  the keyframe is usually older than that window, so Scrypted logs
  `Unable to find sync frame in rtsp prebuffer` and the viewer waits for the
  next live keyframe: **0–6.7 s extra**.
- Snapshots taken from that prebuffer start without a keyframe. The decoder
  conceals the missing data (`concealing ... errors in P frame`), which gives
  the grey, smeared stills.

## Fix 1: re-encode with a short GOP in go2rtc

Add a transcoded stream per camera next to the original one. The transcode
reads from the existing go2rtc stream, so the camera still has **one** HomeKit
session and its Wi-Fi bandwidth does not change.

```yaml
ffmpeg:
  # 1280x720 H.264, keyframe every 8 frames (~0.5 s at 15 fps), no B-frames.
  # -threads 1: one slice per frame. With sliced threads (the zerolatency
  # default) every slice is an IDR NAL and Scrypted detects a far too short
  # keyframe interval (~0.13 s), which shrinks its prebuffer window so it
  # still cannot find the keyframe.
  h264hk: "-c:v libx264 -g 8 -keyint_min 8 -sc_threshold 0 -bf 0 -profile:v main -level:v 4.0 -preset:v superfast -tune:v zerolatency -threads:v 1 -pix_fmt:v yuv420p -b:v 1500k -maxrate 2000k -bufsize 2000k"

streams:
  camera1:
    - hass:<E1_CONFIG_ENTRY_TITLE_1>#maxwidth=1280#maxheight=720#bitrate=1M
  camera1_hk:
    - ffmpeg:camera1#video=h264hk                 # video: transcoded, short GOP
    - rtsp://127.0.0.1:8554/camera1?audio         # audio: AAC-ELD passthrough
```

Notes:

- Let the camera already deliver 1280x720 (`#maxwidth=1280#maxheight=720`).
  Decoding 1080p in software costs noticeably more CPU than 720p.
- `rtsp://127.0.0.1:...` and `ffmpeg:<stream>` connect over loopback, so they
  need no RTSP credentials. The go2rtc API and RTSP auth for LAN clients stay
  unchanged.
- UniFi Protect can use the fast stream too, see
  the section "Fast start in UniFi Protect too" below.

### CPU

Measured on a Home Assistant OS VM with 4 vCPUs on an Intel Pentium Silver
J5040 (no GPU passthrough), with 3 cameras transcoded at 1280x720, 15 fps:

| | VM CPU (of 4 vCPU) | go2rtc add-on |
|---|---|---|
| Passthrough only | ~9 % | ~2 % |
| 3 × `h264hk` (superfast, GOP 8) | ~28 % avg, 40 % peak | ~22 % |

Because Scrypted's prebuffer keeps the `_hk` streams open, the transcode runs
continuously. If CPU is too high, try `-preset:v ultrafast` (lower quality per
bit), a lower bitrate, or `#width=960#height=540` on the ffmpeg source.

### Hardware acceleration (optional)

If the VM or container that runs go2rtc can see an Intel iGPU (`/dev/dri`),
use go2rtc's VAAPI encoder instead of libx264:

```yaml
camera1_hk:
  - ffmpeg:camera1#video=h264#hardware=vaapi#raw=-g 8 -bf 0
  - rtsp://127.0.0.1:8554/camera1?audio
```

This needs the GPU passed through to the HA VM (PCI passthrough or a GVT-g /
SR-IOV virtual function). Check the result with `tools/stream_check.sh` and
verify the keyframe interval with ffprobe.

## Fast start in UniFi Protect too

Protect stores the RTSP URI it got at adoption (e.g. `/camera1` via
onvif-server). Changing the path in onvif-server has no effect until you
re-adopt. Instead, rename the streams in go2rtc so that `/camera1` itself
becomes the short-GOP transcode:

```yaml
streams:
  camera1_src:                                    # raw camera stream (renamed)
    - hass:<E1_CONFIG_ENTRY_TITLE_1>#maxwidth=1280#maxheight=720#bitrate=1M
  camera1:                                        # what Protect AND Scrypted use
    - ffmpeg:camera1_src#video=h264hk
    - rtsp://127.0.0.1:8554/camera1_src?audio
```

- Protect and Scrypted share the same transcode, so there is no extra CPU and
  no extra camera session. Drop the separate `camera1_hk` stream, and point
  Scrypted (stream URL and snapshot URL) at `camera1`.
- RTSP credentials are global in go2rtc, so Protect's login still works for
  the renamed stream.
- After the go2rtc restart, Protect reconnects on its own. If it stays black,
  switch the camera off and on in Protect.
- Measured: first keyframe on `rtsp://.../camera1` 0.94–1.17 s, before 3.9–5.2 s
  on the raw stream. Both include ~0.7 s of client and RTSP setup.
  go2rtc has no GOP cache, so a new RTSP client waits at most one GOP (~0.5 s).

## Fix 2: point Scrypted at the transcoded stream and take clean snapshots

Per camera in Scrypted:

1. **RTSP Camera > RTSP Stream URL**: `rtsp://127.0.0.1:8554/camera1_hk?video&audio`
2. **Snapshot > Snapshot URL**: `http://127.0.0.1:1984/api/frame.jpeg?src=camera1_hk`
   - go2rtc waits for a keyframe before it encodes the JPEG, so the image is
     always complete. With the short GOP this takes < 1 s.
   - Loopback requests to the go2rtc API need no credentials, so nothing
     secret is stored in Scrypted and the API still requires auth from the LAN.
3. **Snapshot > Snapshots from Prebuffer**: `Disabled`
4. Leave HomeKit's debug options at their defaults (no transcoding in Scrypted).
5. Reload the Rebroadcast plugin (or restart Scrypted), then check
   **Streams > Detected Keyframe Interval**: it should show about `0.53`.
   The log should no longer show `Unable to find sync frame`.

HomeKit pairings are not affected by any of this.

## Results

Same setup as above. "First keyframe" is the time from requesting the stream
from Scrypted (the same call the HomeKit plugin makes) until a decodable
keyframe arrives at an ffprobe client on the LAN. It includes ~1.1 s of
client and RTSP setup overhead.

| | Before (E1 GOP 6.7 s) | After (`h264hk`, GOP 0.53 s) |
|---|---|---|
| First keyframe via Scrypted | 3.6–4.4 s | 1.17–1.33 s |
| Of which waiting for a keyframe | ~2.5–3.3 s | 0 s (served from prebuffer) |
| `Unable to find sync frame` in log | every request | none |
| Snapshot | from cache / smeared | 0.7–1.1 s, clean |

In the Home app, live view now starts in about a second, close to what the
camera does when paired with Apple Home directly.
