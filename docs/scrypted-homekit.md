# Re-exporting the cameras to Apple Home with Scrypted (optional)

Once an E1 is paired with Home Assistant (`homekit_controller`), it is no longer
in the Apple Home app. If you still want it there, re-export the go2rtc stream
with [Scrypted](https://github.com/koush/scrypted) (Home Assistant add-on).

Setup that works:

1. Install the Scrypted add-on and the plugins **RTSP Camera**, **Rebroadcast
   (prebuffer)** and **HomeKit**.
2. Add an RTSP camera per E1 with URL
   `rtsp://127.0.0.1:8554/<stream>_hk?video&audio`. This is the transcoded
   stream with a short keyframe interval from
   [`fast-live-view.md`](fast-live-view.md). `rtsp://127.0.0.1:8554/<stream>`
   also works, but then live view takes 3–7 s to start.
   - Scrypted runs with host networking, so it connects from `127.0.0.1`, which
     go2rtc lets through without RTSP credentials. No password is stored in
     Scrypted.
3. In the HomeKit settings of each camera, enable **Standalone Accessory Mode**
   and pair it in the Home app with the QR/pairing code shown in Scrypted.
4. Leave the HomeKit debug options at their defaults (no transcoding).
5. Snapshots: set **Snapshot URL** to
   `http://127.0.0.1:1984/api/frame.jpeg?src=<stream>_hk` and
   **Snapshots from Prebuffer** to `Disabled`. Otherwise tiles can show grey,
   smeared or old stills. See [`fast-live-view.md`](fast-live-view.md).

## How it fits together

go2rtc keeps ONE HomeKit session per camera and fans it out to all consumers
(Scrypted, UniFi Protect, the HA UI). The camera never sees more than one
viewer.

## Things to know

- **Slow live start / funky stills**: the E1 sends a keyframe only every
  ~6.7 s. See [`fast-live-view.md`](fast-live-view.md) for the cause and the
  fix (short-GOP transcode in go2rtc, snapshots via go2rtc).

- **Scrypted passes the camera's H.264 stream through without transcoding.**
  If a camera has to push 1080p at ~4 Mbit/s over weak Wi-Fi, Scrypted logs
  `packet loss` / `fua packet missing`, and Home app live view stops after a
  few seconds. Fix it in go2rtc with
  `#maxwidth=1280#maxheight=720#bitrate=1M` (see the README).
- **After changing or restarting go2rtc**, Scrypted's prebuffer reconnects on
  its own: you will see `ECONNREFUSED 127.0.0.1:8554` for a few seconds, then it
  recovers. Close and reopen the Home app afterwards.
- **"Scrypted Server Addresses are not set"** is only a warning. If streaming to
  Apple devices is unreliable, set the wired IP of the HA host in Scrypted's
  settings.
