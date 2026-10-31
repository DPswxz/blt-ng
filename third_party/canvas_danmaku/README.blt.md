Vendored from canvas_danmaku 0.2.7 (Predidit), MIT license in LICENSE.

BLT changes: vsync-driven CustomPainter repaint for scrolling comments (no widget
build per animation frame), absolute elapsed-time positions, no per-frame nested
PictureRecorder, disposed temporary TextPainters, a single cancellable cleanup
timer, rebuild static layers only when necessary, no advanced animation layer
unless advanced comments exist. Public controller API remains compatible.

BLT 1.0.25 samples scroll positions from Flutter's vsync frame timestamp rather
than paint-time wall-clock samples; pause/clear and empty queues reset the frame
origin. Display cadence is requested by the app rather than the video Surface.

BLT 1.0.27 applies opacity to cached text/stroke paragraphs rather than compositing
the entire normal danmaku layer through Opacity. Advanced danmaku keeps its own
Opacity wrapper. Font metrics reuse the fill paragraph; occupied tracks reject
comments before stroke shaping. Speed changes clear active comments so positions
do not jump when duration changes.
