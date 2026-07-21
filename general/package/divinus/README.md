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
