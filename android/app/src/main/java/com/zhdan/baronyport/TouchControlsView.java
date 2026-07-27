package com.zhdan.baronyport;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.hardware.input.InputManager;
import android.os.Build;
import android.util.Log;
import android.util.SparseArray;
import android.view.DisplayCutout;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;

import org.libsdl.app.SDLControllerManager;

import java.util.ArrayList;
import java.util.List;

/**
 * Transparent Android overlay that exposes multitouch controls to SDL as a
 * conventional six-axis game controller. Barony therefore uses the same input
 * bindings for touch and physical controllers.
 */
final class TouchControlsView extends View implements InputManager.InputDeviceListener {
    static final int LAYOUT_MENU = 0;
    static final int LAYOUT_GAMEPLAY = 1;
    static final int LAYOUT_UI = 2;

    private static final String TAG = "BaronyTouch";
    private static final int VIRTUAL_DEVICE_ID = 0x42524E59; // "BRNY"
    private static final int AXIS_LEFT_X = 0;
    private static final int AXIS_LEFT_Y = 1;
    private static final int AXIS_RIGHT_X = 2;
    private static final int AXIS_RIGHT_Y = 3;
    private static final int AXIS_LEFT_TRIGGER = 4;
    private static final int AXIS_RIGHT_TRIGGER = 5;
    private static final int AXIS_MASK = 0x3f;
    private static final int BUTTON_MASK =
            (1 << 0)   // A
                    | (1 << 1)   // B
                    | (1 << 2)   // X
                    | (1 << 3)   // Y
                    | (1 << 4)   // Back
                    | (1 << 6)   // Start
                    | (1 << 9)   // Left shoulder
                    | (1 << 10)  // Right shoulder
                    | (1 << 11)  // D-pad up
                    | (1 << 12)  // D-pad down
                    | (1 << 13)  // D-pad left
                    | (1 << 14); // D-pad right

    private static final int TARGET_LEFT_STICK = 1;
    private static final int TARGET_RIGHT_STICK = 2;
    private static final int TARGET_BUTTON = 3;
    private static final int SHAPE_CIRCLE = 0;
    private static final int SHAPE_PILL = 1;

    private final InputManager inputManager;
    private final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final List<VirtualButton> buttons = new ArrayList<>();
    private final SparseArray<TouchTarget> activeTouches = new SparseArray<>();
    private final VirtualStick leftStick = new VirtualStick(AXIS_LEFT_X, AXIS_LEFT_Y, "MOVE");
    private final VirtualStick rightStick = new VirtualStick(AXIS_RIGHT_X, AXIS_RIGHT_Y, "LOOK");
    private final RectF moveZone = new RectF();
    private final RectF lookZone = new RectF();
    private final RectF gameplayUiPassThroughZone = new RectF();
    private final Runnable refreshInputModeRunnable = this::refreshInputMode;

    private boolean controllerRegistered;
    private boolean destroyed;
    private boolean physicalControllerPresent;
    private boolean floatingMoveEnabled;
    private boolean floatingLookEnabled;
    private int layoutMode = LAYOUT_MENU;
    private int safeLeft;
    private int safeTop;
    private int safeRight;
    private int safeBottom;
    private float moveGuideX;
    private float moveGuideY;
    private float moveStickRadius;
    private float lookGuideX;
    private float lookGuideY;
    private float lookStickRadius;

    TouchControlsView(Context context) {
        super(context);
        inputManager = (InputManager) context.getSystemService(Context.INPUT_SERVICE);
        setBackgroundColor(Color.TRANSPARENT);
        setWillNotDraw(false);
        setFocusable(false);
        setClickable(true);

        fillPaint.setStyle(Paint.Style.FILL);
        strokePaint.setStyle(Paint.Style.STROKE);
        strokePaint.setStrokeWidth(dp(1.5f));
        textPaint.setTextAlign(Paint.Align.CENTER);
        textPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));

        setOnApplyWindowInsetsListener((view, insets) -> {
            updateSafeInsets(insets);
            rebuildLayout(getWidth(), getHeight());
            return insets;
        });

        if (inputManager != null) {
            inputManager.registerInputDeviceListener(this, null);
        }
        Log.i(TAG, "BARONY_ANDROID_TOUCH_CONTROLLER_READY");
        postDelayed(refreshInputModeRunnable, 500);
    }

    void setLayoutMode(int mode) {
        if (mode < LAYOUT_MENU || mode > LAYOUT_UI || layoutMode == mode) {
            return;
        }
        layoutMode = mode;
        rebuildLayout(getWidth(), getHeight());
    }

    void onHostResume() {
        post(refreshInputModeRunnable);
    }

    void onHostPause() {
        releaseAllControls();
    }

    void shutdown() {
        if (destroyed) {
            return;
        }
        destroyed = true;
        removeCallbacks(refreshInputModeRunnable);
        releaseAllControls();
        unregisterVirtualController();
        if (inputManager != null) {
            inputManager.unregisterInputDeviceListener(this);
        }
    }

    @Override
    public void onInputDeviceAdded(int deviceId) {
        post(refreshInputModeRunnable);
    }

    @Override
    public void onInputDeviceRemoved(int deviceId) {
        post(refreshInputModeRunnable);
    }

    @Override
    public void onInputDeviceChanged(int deviceId) {
        post(refreshInputModeRunnable);
    }

    private void refreshInputMode() {
        if (destroyed) {
            return;
        }
        boolean hasPhysicalController = hasPhysicalController();
        if (hasPhysicalController) {
            releaseAllControls();
            unregisterVirtualController();
            setVisibility(GONE);
        } else {
            registerVirtualController();
            setVisibility(controllerRegistered ? VISIBLE : GONE);
        }

        if (physicalControllerPresent != hasPhysicalController) {
            physicalControllerPresent = hasPhysicalController;
            Log.i(TAG, hasPhysicalController
                    ? "BARONY_ANDROID_TOUCH_HIDDEN_FOR_GAMEPAD"
                    : "BARONY_ANDROID_TOUCH_SHOWN");
        }
    }

    private boolean hasPhysicalController() {
        if (inputManager == null) {
            return false;
        }
        for (int deviceId : InputDevice.getDeviceIds()) {
            InputDevice device = InputDevice.getDevice(deviceId);
            if (device == null || device.isVirtual()) {
                continue;
            }
            int sources = device.getSources();
            boolean gamepad = (sources & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD;
            boolean joystick = (sources & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
            if (gamepad || joystick) {
                return true;
            }
        }
        return false;
    }

    private void registerVirtualController() {
        if (controllerRegistered || destroyed) {
            return;
        }
        try {
            int result = SDLControllerManager.nativeAddJoystick(
                    VIRTUAL_DEVICE_ID,
                    "Barony Android Touch Controller",
                    "barony-android-touch-v2",
                    0,
                    0,
                    false,
                    BUTTON_MASK,
                    6,
                    AXIS_MASK,
                    0,
                    0);
            controllerRegistered = result >= 0;
            if (controllerRegistered) {
                Log.i(TAG, "BARONY_ANDROID_TOUCH_CONTROLLER_ADDED");
                invalidate();
            } else {
                Log.w(TAG, "Unable to add the SDL touch controller; result=" + result);
            }
        } catch (UnsatisfiedLinkError error) {
            Log.w(TAG, "SDL controller JNI is not ready; retrying", error);
            postDelayed(refreshInputModeRunnable, 500);
        }
    }

    private void unregisterVirtualController() {
        if (!controllerRegistered) {
            return;
        }
        try {
            SDLControllerManager.nativeRemoveJoystick(VIRTUAL_DEVICE_ID);
        } catch (UnsatisfiedLinkError error) {
            Log.w(TAG, "Unable to remove the SDL touch controller", error);
        }
        controllerRegistered = false;
        Log.i(TAG, "BARONY_ANDROID_TOUCH_CONTROLLER_REMOVED");
    }

    private void updateSafeInsets(WindowInsets insets) {
        safeLeft = insets.getSystemWindowInsetLeft();
        safeTop = insets.getSystemWindowInsetTop();
        safeRight = insets.getSystemWindowInsetRight();
        safeBottom = insets.getSystemWindowInsetBottom();
        if (Build.VERSION.SDK_INT >= 28) {
            DisplayCutout cutout = insets.getDisplayCutout();
            if (cutout != null) {
                safeLeft = Math.max(safeLeft, cutout.getSafeInsetLeft());
                safeTop = Math.max(safeTop, cutout.getSafeInsetTop());
                safeRight = Math.max(safeRight, cutout.getSafeInsetRight());
                safeBottom = Math.max(safeBottom, cutout.getSafeInsetBottom());
            }
        }
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        rebuildLayout(width, height);
    }

    private void rebuildLayout(int width, int height) {
        releaseAllControls();
        buttons.clear();
        floatingMoveEnabled = false;
        floatingLookEnabled = false;
        moveZone.setEmpty();
        lookZone.setEmpty();
        gameplayUiPassThroughZone.setEmpty();

        if (width <= 0 || height <= 0) {
            return;
        }

        float left = safeLeft + dp(12.0f);
        float top = safeTop + dp(10.0f);
        float usableWidth = Math.max(1.0f, width - safeLeft - safeRight - dp(24.0f));
        float usableHeight = Math.max(1.0f, height - safeTop - safeBottom - dp(20.0f));
        float shortSide = Math.min(usableWidth, usableHeight);

        if (layoutMode == LAYOUT_GAMEPLAY) {
            buildGameplayLayout(left, top, usableWidth, usableHeight, shortSide);
        } else if (layoutMode == LAYOUT_UI) {
            buildUiLayout(left, top, usableWidth, usableHeight, shortSide);
        } else {
            buildMenuLayout(left, top, usableWidth, usableHeight, shortSide);
        }
        invalidate();
    }

    private void buildMenuLayout(float left, float top, float width, float height,
                                 float shortSide) {
        addDpad(left + width * 0.13f, top + height * 0.75f, shortSide);
        addFaceButtons(left + width * 0.90f, top + height * 0.75f, shortSide);
        float pillRadius = shortSide * 0.037f;
        addKeyPill("LB", left + width * 0.06f, top + height * 0.10f, pillRadius,
                KeyEvent.KEYCODE_BUTTON_L1);
        addKeyPill("RB", left + width * 0.94f, top + height * 0.10f, pillRadius,
                KeyEvent.KEYCODE_BUTTON_R1);
    }

    private void buildUiLayout(float left, float top, float width, float height,
                               float shortSide) {
        // Barony's inventory and character sheet occupy both screen edges.
        // Keep controller-style navigation in the open center viewport so the
        // item grids, equipment slots, and character actions remain tappable.
        addDpad(left + width * 0.35f, top + height * 0.75f, shortSide);
        addFaceButtons(left + width * 0.65f, top + height * 0.75f, shortSide);

        float pillRadius = shortSide * 0.035f;
        addKeyPill("LB", left + width * 0.32f, top + height * 0.10f, pillRadius,
                KeyEvent.KEYCODE_BUTTON_L1);
        addKeyPill("INV", left + width * 0.44f, top + height * 0.10f, pillRadius,
                KeyEvent.KEYCODE_BUTTON_SELECT);
        addKeyPill("II", left + width * 0.56f, top + height * 0.10f, pillRadius,
                KeyEvent.KEYCODE_BUTTON_START);
        addKeyPill("RB", left + width * 0.68f, top + height * 0.10f, pillRadius,
                KeyEvent.KEYCODE_BUTTON_R1);
    }

    private void buildGameplayLayout(float left, float top, float width, float height,
                                     float shortSide) {
        floatingMoveEnabled = true;
        floatingLookEnabled = true;

        moveStickRadius = shortSide * 0.105f;
        moveZone.set(
                left,
                top + height * 0.30f,
                left + width * 0.50f,
                top + height * 0.96f);
        moveGuideX = left + width * 0.25f;
        moveGuideY = top + height * 0.76f;
        leftStick.setGeometry(moveGuideX, moveGuideY, moveStickRadius);

        lookStickRadius = shortSide * 0.105f;
        lookZone.set(
                left + width * 0.50f,
                top + height * 0.30f,
                left + width,
                top + height * 0.96f);
        lookGuideX = left + width * 0.72f;
        lookGuideY = top + height * 0.76f;
        rightStick.setGeometry(lookGuideX, lookGuideY, lookStickRadius);

        // Leave the visible hotbar area to SDL so items can still be selected
        // directly. This applies only when the hotbar touch starts the gesture;
        // an already-owned multitouch gesture remains within this overlay.
        gameplayUiPassThroughZone.set(
                left + width * 0.30f,
                top + height * 0.84f,
                left + width * 0.70f,
                top + height);

        addFaceButtons(left + width * 0.91f, top + height * 0.76f, shortSide);
        addAxisPill("DEF", left + width * 0.18f, top + height * 0.48f,
                shortSide * 0.046f, AXIS_LEFT_TRIGGER);
        addKeyPill("CAST", left + width * 0.06f, top + height * 0.31f,
                shortSide * 0.038f, KeyEvent.KEYCODE_BUTTON_L1);
        addAxisPill("ATK", left + width * 0.80f, top + height * 0.47f,
                shortSide * 0.052f, AXIS_RIGHT_TRIGGER);
        addKeyPill("RB", left + width * 0.94f, top + height * 0.31f,
                shortSide * 0.038f, KeyEvent.KEYCODE_BUTTON_R1);
        addKeyPill("INV", left + width * 0.06f, top + height * 0.10f,
                shortSide * 0.034f, KeyEvent.KEYCODE_BUTTON_SELECT);
        addKeyPill("II", left + width * 0.94f, top + height * 0.10f,
                shortSide * 0.034f, KeyEvent.KEYCODE_BUTTON_START);
    }

    private void addDpad(float centerX, float centerY, float shortSide) {
        float radius = shortSide * 0.035f;
        float offset = shortSide * 0.085f;
        addKeyButton("↑", centerX, centerY - offset, radius, KeyEvent.KEYCODE_DPAD_UP);
        addKeyButton("↓", centerX, centerY + offset, radius, KeyEvent.KEYCODE_DPAD_DOWN);
        addKeyButton("←", centerX - offset, centerY, radius, KeyEvent.KEYCODE_DPAD_LEFT);
        addKeyButton("→", centerX + offset, centerY, radius, KeyEvent.KEYCODE_DPAD_RIGHT);
    }

    private void addFaceButtons(float centerX, float centerY, float shortSide) {
        float radius = shortSide * 0.040f;
        float offset = radius * 1.78f;
        addKeyButton("A", centerX, centerY + offset, radius, KeyEvent.KEYCODE_BUTTON_A);
        addKeyButton("B", centerX + offset, centerY, radius, KeyEvent.KEYCODE_BUTTON_B);
        addKeyButton("X", centerX - offset, centerY, radius, KeyEvent.KEYCODE_BUTTON_X);
        addKeyButton("Y", centerX, centerY - offset, radius, KeyEvent.KEYCODE_BUTTON_Y);
    }

    private void addKeyButton(String label, float x, float y, float radius, int keyCode) {
        buttons.add(VirtualButton.forKey(label, x, y, radius, SHAPE_CIRCLE, keyCode, dp(24.0f)));
    }

    private void addKeyPill(String label, float x, float y, float radius, int keyCode) {
        buttons.add(VirtualButton.forKey(label, x, y, radius, SHAPE_PILL, keyCode, dp(24.0f)));
    }

    private void addAxisPill(String label, float x, float y, float radius, int axis) {
        buttons.add(VirtualButton.forAxis(label, x, y, radius, SHAPE_PILL, axis, dp(24.0f)));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (!controllerRegistered) {
            return;
        }
        if (floatingMoveEnabled) {
            if (leftStick.pointerId >= 0) {
                drawStick(canvas, leftStick);
            } else {
                drawStickGuide(canvas, moveGuideX, moveGuideY, moveStickRadius, "MOVE");
            }
        }
        if (floatingLookEnabled) {
            if (rightStick.pointerId >= 0) {
                drawStick(canvas, rightStick);
            } else {
                drawStickGuide(canvas, lookGuideX, lookGuideY, lookStickRadius, "LOOK");
            }
        }
        for (VirtualButton button : buttons) {
            drawButton(canvas, button);
        }
    }

    private void drawStick(Canvas canvas, VirtualStick stick) {
        boolean active = stick.pointerId >= 0;
        fillPaint.setColor(Color.argb(active ? 72 : 42, 15, 22, 31));
        strokePaint.setColor(Color.argb(active ? 185 : 100, 255, 255, 255));
        canvas.drawCircle(stick.centerX, stick.centerY, stick.radius, fillPaint);
        canvas.drawCircle(stick.centerX, stick.centerY, stick.radius, strokePaint);

        float knobRadius = stick.radius * 0.42f;
        fillPaint.setColor(Color.argb(active ? 150 : 68, 210, 225, 240));
        canvas.drawCircle(stick.knobX, stick.knobY, knobRadius, fillPaint);
        canvas.drawCircle(stick.knobX, stick.knobY, knobRadius, strokePaint);

        textPaint.setColor(Color.argb(active ? 220 : 145, 255, 255, 255));
        textPaint.setTextSize(Math.max(dp(10.0f), stick.radius * 0.18f));
        Paint.FontMetrics metrics = textPaint.getFontMetrics();
        float baseline = stick.centerY + stick.radius + dp(5.0f) - metrics.ascent;
        canvas.drawText(stick.label, stick.centerX, baseline, textPaint);
    }

    private void drawStickGuide(Canvas canvas, float centerX, float centerY,
                                float stickRadius, String label) {
        float guideRadius = Math.max(dp(14.0f), stickRadius * 0.28f);
        fillPaint.setColor(Color.argb(26, 15, 22, 31));
        strokePaint.setColor(Color.argb(72, 255, 255, 255));
        canvas.drawCircle(centerX, centerY, guideRadius, fillPaint);
        canvas.drawCircle(centerX, centerY, guideRadius, strokePaint);
        textPaint.setColor(Color.argb(105, 255, 255, 255));
        textPaint.setTextSize(Math.max(dp(9.0f), guideRadius * 0.52f));
        Paint.FontMetrics metrics = textPaint.getFontMetrics();
        float baseline = centerY - (metrics.ascent + metrics.descent) * 0.5f;
        canvas.drawText(label, centerX, baseline, textPaint);
    }

    private void drawButton(Canvas canvas, VirtualButton button) {
        boolean pressed = button.pointerId >= 0;
        fillPaint.setColor(pressed
                ? Color.argb(170, 66, 126, 185)
                : Color.argb(42, 15, 22, 31));
        strokePaint.setColor(Color.argb(pressed ? 210 : 100, 255, 255, 255));

        if (button.shape == SHAPE_PILL) {
            RectF bounds = button.getVisualBounds();
            float corner = bounds.height() * 0.5f;
            canvas.drawRoundRect(bounds, corner, corner, fillPaint);
            canvas.drawRoundRect(bounds, corner, corner, strokePaint);
        } else {
            canvas.drawCircle(button.centerX, button.centerY, button.radius, fillPaint);
            canvas.drawCircle(button.centerX, button.centerY, button.radius, strokePaint);
        }

        textPaint.setColor(Color.argb(pressed ? 255 : 165, 255, 255, 255));
        textPaint.setTextSize(Math.max(dp(10.0f), button.radius * 0.56f));
        Paint.FontMetrics metrics = textPaint.getFontMetrics();
        float baseline = button.centerY - (metrics.ascent + metrics.descent) * 0.5f;
        canvas.drawText(button.label, button.centerX, baseline, textPaint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (!controllerRegistered || getVisibility() != VISIBLE) {
            return false;
        }
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                // Declining an unmatched initial pointer lets SDL's view below
                // this overlay receive Barony's existing finger UI events.
                return handlePointerDown(event, event.getActionIndex());
            case MotionEvent.ACTION_POINTER_DOWN:
                handlePointerDown(event, event.getActionIndex());
                return true;
            case MotionEvent.ACTION_MOVE:
                handlePointerMove(event);
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
                handlePointerUp(event.getPointerId(event.getActionIndex()));
                return true;
            case MotionEvent.ACTION_CANCEL:
                releaseAllControls();
                return true;
            default:
                return true;
        }
    }

    private boolean handlePointerDown(MotionEvent event, int pointerIndex) {
        int pointerId = event.getPointerId(pointerIndex);
        float x = event.getX(pointerIndex);
        float y = event.getY(pointerIndex);

        for (int i = buttons.size() - 1; i >= 0; --i) {
            VirtualButton button = buttons.get(i);
            if (button.pointerId < 0 && button.contains(x, y)) {
                button.pointerId = pointerId;
                activeTouches.put(pointerId, TouchTarget.forButton(button));
                sendButton(button, true);
                invalidate();
                return true;
            }
        }
        if (!gameplayUiPassThroughZone.isEmpty()
                && gameplayUiPassThroughZone.contains(x, y)) {
            return false;
        }
        if (floatingMoveEnabled && leftStick.pointerId < 0 && moveZone.contains(x, y)) {
            float centerX = clamp(x, moveZone.left + moveStickRadius,
                    moveZone.right - moveStickRadius);
            float centerY = clamp(y, moveZone.top + moveStickRadius,
                    moveZone.bottom - moveStickRadius);
            leftStick.setGeometry(centerX, centerY, moveStickRadius);
            leftStick.pointerId = pointerId;
            activeTouches.put(pointerId, TouchTarget.forStick(TARGET_LEFT_STICK, leftStick));
            updateStick(leftStick, x, y);
            return true;
        }
        if (floatingLookEnabled && rightStick.pointerId < 0 && lookZone.contains(x, y)) {
            float centerX = clamp(x, lookZone.left + lookStickRadius,
                    lookZone.right - lookStickRadius);
            float centerY = clamp(y, lookZone.top + lookStickRadius,
                    lookZone.bottom - lookStickRadius);
            rightStick.setGeometry(centerX, centerY, lookStickRadius);
            rightStick.pointerId = pointerId;
            activeTouches.put(pointerId, TouchTarget.forStick(TARGET_RIGHT_STICK, rightStick));
            updateStick(rightStick, x, y);
            return true;
        }
        return false;
    }

    private void handlePointerMove(MotionEvent event) {
        for (int i = 0; i < activeTouches.size(); ++i) {
            int pointerId = activeTouches.keyAt(i);
            TouchTarget target = activeTouches.valueAt(i);
            if (target.kind == TARGET_BUTTON) {
                continue;
            }
            int pointerIndex = event.findPointerIndex(pointerId);
            if (pointerIndex >= 0) {
                updateStick(target.stick, event.getX(pointerIndex), event.getY(pointerIndex));
            }
        }
    }

    private void handlePointerUp(int pointerId) {
        TouchTarget target = activeTouches.get(pointerId);
        if (target == null) {
            return;
        }
        if (target.kind == TARGET_BUTTON) {
            target.button.pointerId = -1;
            sendButton(target.button, false);
        } else {
            releaseStick(target.stick);
        }
        activeTouches.remove(pointerId);
        invalidate();
    }

    private void updateStick(VirtualStick stick, float x, float y) {
        float dx = x - stick.centerX;
        float dy = y - stick.centerY;
        float distance = (float) Math.sqrt(dx * dx + dy * dy);
        if (distance > stick.radius && distance > 0.0f) {
            float scale = stick.radius / distance;
            dx *= scale;
            dy *= scale;
        }
        stick.knobX = stick.centerX + dx;
        stick.knobY = stick.centerY + dy;
        float axisX = clamp(dx / stick.radius);
        float axisY = clamp(dy / stick.radius);
        if (Math.abs(axisX - stick.valueX) > 0.005f) {
            stick.valueX = axisX;
            SDLControllerManager.onNativeJoy(VIRTUAL_DEVICE_ID, stick.axisX, axisX);
        }
        if (Math.abs(axisY - stick.valueY) > 0.005f) {
            stick.valueY = axisY;
            SDLControllerManager.onNativeJoy(VIRTUAL_DEVICE_ID, stick.axisY, axisY);
        }
        invalidate();
    }

    private void releaseStick(VirtualStick stick) {
        stick.pointerId = -1;
        stick.knobX = stick.centerX;
        stick.knobY = stick.centerY;
        stick.valueX = 0.0f;
        stick.valueY = 0.0f;
        if (controllerRegistered) {
            SDLControllerManager.onNativeJoy(VIRTUAL_DEVICE_ID, stick.axisX, 0.0f);
            SDLControllerManager.onNativeJoy(VIRTUAL_DEVICE_ID, stick.axisY, 0.0f);
        }
    }

    private void sendButton(VirtualButton button, boolean pressed) {
        if (!controllerRegistered) {
            return;
        }
        if (button.axis >= 0) {
            SDLControllerManager.onNativeJoy(
                    VIRTUAL_DEVICE_ID, button.axis, pressed ? 1.0f : 0.0f);
        } else if (pressed) {
            SDLControllerManager.onNativePadDown(VIRTUAL_DEVICE_ID, button.keyCode);
        } else {
            SDLControllerManager.onNativePadUp(VIRTUAL_DEVICE_ID, button.keyCode);
        }
    }

    private void releaseAllControls() {
        releaseStick(leftStick);
        releaseStick(rightStick);
        for (VirtualButton button : buttons) {
            if (button.pointerId >= 0) {
                button.pointerId = -1;
                sendButton(button, false);
            }
        }
        activeTouches.clear();
        invalidate();
    }

    private float clamp(float value) {
        return Math.max(-1.0f, Math.min(1.0f, value));
    }

    private float clamp(float value, float minimum, float maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    private float dp(float value) {
        return value * getResources().getDisplayMetrics().density;
    }

    private static final class VirtualStick {
        final int axisX;
        final int axisY;
        final String label;
        float centerX;
        float centerY;
        float radius;
        float knobX;
        float knobY;
        float valueX;
        float valueY;
        int pointerId = -1;

        VirtualStick(int axisX, int axisY, String label) {
            this.axisX = axisX;
            this.axisY = axisY;
            this.label = label;
        }

        void setGeometry(float centerX, float centerY, float radius) {
            this.centerX = centerX;
            this.centerY = centerY;
            this.radius = radius;
            this.knobX = centerX;
            this.knobY = centerY;
        }

        boolean contains(float x, float y) {
            float dx = x - centerX;
            float dy = y - centerY;
            float hitRadius = radius * 1.18f;
            return dx * dx + dy * dy <= hitRadius * hitRadius;
        }
    }

    private static final class VirtualButton {
        final String label;
        final float centerX;
        final float centerY;
        final float radius;
        final int shape;
        final int keyCode;
        final int axis;
        final float hitHalfWidth;
        final float hitHalfHeight;
        int pointerId = -1;

        private VirtualButton(String label, float centerX, float centerY, float radius,
                              int shape, int keyCode, int axis, float minimumHitRadius) {
            this.label = label;
            this.centerX = centerX;
            this.centerY = centerY;
            this.radius = radius;
            this.shape = shape;
            this.keyCode = keyCode;
            this.axis = axis;
            if (shape == SHAPE_PILL) {
                hitHalfWidth = Math.max(radius * 1.55f, minimumHitRadius);
                hitHalfHeight = Math.max(radius * 0.95f, minimumHitRadius);
            } else {
                hitHalfWidth = Math.max(radius * 1.22f, minimumHitRadius);
                hitHalfHeight = hitHalfWidth;
            }
        }

        static VirtualButton forKey(String label, float x, float y, float radius, int shape,
                                    int keyCode, float minimumHitRadius) {
            return new VirtualButton(label, x, y, radius, shape, keyCode, -1,
                    minimumHitRadius);
        }

        static VirtualButton forAxis(String label, float x, float y, float radius, int shape,
                                     int axis, float minimumHitRadius) {
            return new VirtualButton(label, x, y, radius, shape, 0, axis,
                    minimumHitRadius);
        }

        RectF getVisualBounds() {
            return new RectF(
                    centerX - radius * 1.35f,
                    centerY - radius * 0.72f,
                    centerX + radius * 1.35f,
                    centerY + radius * 0.72f);
        }

        boolean contains(float x, float y) {
            if (shape == SHAPE_PILL) {
                return Math.abs(x - centerX) <= hitHalfWidth
                        && Math.abs(y - centerY) <= hitHalfHeight;
            }
            float dx = x - centerX;
            float dy = y - centerY;
            return dx * dx + dy * dy <= hitHalfWidth * hitHalfWidth;
        }
    }

    private static final class TouchTarget {
        final int kind;
        final VirtualStick stick;
        final VirtualButton button;

        private TouchTarget(int kind, VirtualStick stick, VirtualButton button) {
            this.kind = kind;
            this.stick = stick;
            this.button = button;
        }

        static TouchTarget forStick(int kind, VirtualStick stick) {
            return new TouchTarget(kind, stick, null);
        }

        static TouchTarget forButton(VirtualButton button) {
            return new TouchTarget(TARGET_BUTTON, null, button);
        }
    }
}
