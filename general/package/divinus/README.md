# ssc30kq Ultimate Divinus test runtime

The `ssc30kq_ultimate` image includes the complete Infinity6E user-space
library bundle for Divinus testing. Divinus is intentionally manual-only:
`/etc/init.d/divinus` has no `S*` boot prefix, so Majestic remains the default
camera daemon after boot.

On the camera, test Divinus as follows:

1. Stop Majestic: `/etc/init.d/S95majestic stop`
2. Start Divinus: `/etc/init.d/divinus start`
3. Verify the stream using `/etc/divinus.yaml`.
4. Stop Divinus before starting Majestic again: `/etc/init.d/divinus stop`

The service refuses to start while Majestic is running.

The supplied GC4653 configuration starts the 2560x1440 H.264 main stream at
15 fps. A 1024x576 hardware-scaled substream is available but disabled by
default while main-stream stability is validated. Enable the `substream`
section when both streams are wanted:

- `rtsp://CAMERA_IP:554/main` — 2560x1440 at 15 fps
- `rtsp://CAMERA_IP:554/sub` — 1024x576 at 15 fps

The substream uses a second hardware scaler and encoder channel; it is not
CPU-scaled. UDP streaming and MJPEG are also disabled by default.
