Vendored from canvas_danmaku 0.2.7 (Predidit), MIT license in LICENSE.

BLT changes: vsync-driven CustomPainter repaint for scrolling comments (no widget
build per animation frame), absolute elapsed-time positions, no per-frame nested
PictureRecorder, disposed temporary TextPainters, a single cancellable cleanup
timer, rebuild static layers only when necessary, no advanced animation layer
unless advanced comments exist. Public controller API remains compatible.
