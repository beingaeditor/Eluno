package app.eluno.mobile;

import android.content.Context;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.widget.ImageView;

/** Pinch zoom plus an accessible click action for TalkBack and keyboard users. */
public final class ZoomImageView extends ImageView {
    private float zoom = 1;
    private boolean scaled;
    private final ScaleGestureDetector detector;

    public ZoomImageView(Context context) {
        super(context);
        setContentDescription("Photo. Activate to cycle zoom. Pinch to adjust zoom.");
        setFocusable(true);
        setOnClickListener(view -> applyZoom(zoom >= 4 ? 1 : Math.min(4, zoom * 2)));
        detector = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScale(ScaleGestureDetector gesture) {
                scaled = true;
                applyZoom(Math.max(1, Math.min(4, zoom * gesture.getScaleFactor())));
                return true;
            }
        });
    }

    private void applyZoom(float value) { zoom = value; setScaleX(zoom); setScaleY(zoom); }
    @Override public boolean onTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) scaled = false;
        detector.onTouchEvent(event);
        if (event.getActionMasked() == MotionEvent.ACTION_UP && !scaled) performClick();
        return true;
    }
    @Override public boolean performClick() { super.performClick(); return true; }
}
