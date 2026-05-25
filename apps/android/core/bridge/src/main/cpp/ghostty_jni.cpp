#include <jni.h>

#include <android/native_window_jni.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <atomic>
#include <cstdio>
#include <mutex>
#include <string>

#include "ghostty.h"

namespace {

constexpr const char* kLogTag = "LitterGhostty";

static JavaVM* g_jvm = nullptr;

struct AndroidGhosttySurface {
    ANativeWindow* window = nullptr;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface egl_surface = EGL_NO_SURFACE;
    ghostty_config_t config = nullptr;
    ghostty_app_t app = nullptr;
    ghostty_surface_t surface = nullptr;
    uint32_t width = 1;
    uint32_t height = 1;
    float scale = 1.0f;
    bool rendered_during_tick = false;

    // Input callback (Ghostty -> Kotlin). Captured via nativeSetInputCallback.
    // The Kotlin side is a `GhosttyInputCallback` fun interface with `onInput(ByteArray)`.
    jobject input_callback = nullptr;       // NewGlobalRef
    jmethodID input_callback_method = nullptr;
    std::atomic<bool> input_logged_once { false };

    // Wakeup listener (Ghostty -> Kotlin). Triggered from
    // `androidGhosttyWakeup`; Kotlin posts a single Choreographer frame.
    jobject wakeup_listener = nullptr;      // NewGlobalRef
    jmethodID wakeup_listener_method = nullptr;
};

AndroidGhosttySurface* fromHandle(jlong handle) {
    return reinterpret_cast<AndroidGhosttySurface*>(handle);
}

int ensureGhosttyInitialized() {
    static std::once_flag once;
    static int result = 1;
    std::call_once(once, [] {
        char arg0[] = "litter";
        char* argv[] = { arg0 };
        result = ghostty_init(1, argv);
    });
    return result;
}

void logEglError(const char* message) {
    __android_log_print(ANDROID_LOG_WARN, kLogTag, "%s: EGL error 0x%x", message, eglGetError());
}

bool canCreateEglDisplay() {
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        return false;
    }
    EGLint major = 0;
    EGLint minor = 0;
    if (eglInitialize(display, &major, &minor) != EGL_TRUE) {
        return false;
    }
    eglTerminate(display);
    return true;
}

bool createEgl(AndroidGhosttySurface* state) {
    state->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (state->display == EGL_NO_DISPLAY) {
        logEglError("eglGetDisplay failed");
        return false;
    }

    EGLint major = 0;
    EGLint minor = 0;
    if (eglInitialize(state->display, &major, &minor) != EGL_TRUE) {
        logEglError("eglInitialize failed");
        state->display = EGL_NO_DISPLAY;
        return false;
    }

    const EGLint configAttribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };

    EGLConfig config = nullptr;
    EGLint configCount = 0;
    if (eglChooseConfig(state->display, configAttribs, &config, 1, &configCount) != EGL_TRUE ||
        configCount == 0) {
        logEglError("eglChooseConfig failed");
        return false;
    }

    state->egl_surface = eglCreateWindowSurface(state->display, config, state->window, nullptr);
    if (state->egl_surface == EGL_NO_SURFACE) {
        logEglError("eglCreateWindowSurface failed");
        return false;
    }

    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE,
    };
    state->context = eglCreateContext(state->display, config, EGL_NO_CONTEXT, contextAttribs);
    if (state->context == EGL_NO_CONTEXT) {
        logEglError("eglCreateContext failed");
        return false;
    }

    if (eglMakeCurrent(state->display, state->egl_surface, state->egl_surface, state->context) != EGL_TRUE) {
        logEglError("eglMakeCurrent failed");
        return false;
    }
    const GLubyte* version = glGetString(GL_VERSION);
    if (version != nullptr) {
        __android_log_print(ANDROID_LOG_INFO, kLogTag, "created EGL context: %s", version);
    }
    eglSwapInterval(state->display, 1);
    return true;
}

void destroyEgl(AndroidGhosttySurface* state) {
    if (state->display == EGL_NO_DISPLAY) {
        return;
    }
    eglMakeCurrent(state->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (state->context != EGL_NO_CONTEXT) {
        eglDestroyContext(state->display, state->context);
        state->context = EGL_NO_CONTEXT;
    }
    if (state->egl_surface != EGL_NO_SURFACE) {
        eglDestroySurface(state->display, state->egl_surface);
        state->egl_surface = EGL_NO_SURFACE;
    }
    eglTerminate(state->display);
    state->display = EGL_NO_DISPLAY;
}

bool makeCurrent(AndroidGhosttySurface* state) {
    if (state == nullptr ||
        state->display == EGL_NO_DISPLAY ||
        state->egl_surface == EGL_NO_SURFACE ||
        state->context == EGL_NO_CONTEXT) {
        return false;
    }
    if (eglMakeCurrent(state->display, state->egl_surface, state->egl_surface, state->context) != EGL_TRUE) {
        logEglError("eglMakeCurrent failed");
        return false;
    }
    return true;
}

void drawSurface(AndroidGhosttySurface* state) {
    if (state == nullptr || state->surface == nullptr || !makeCurrent(state)) {
        return;
    }
    ghostty_surface_draw(state->surface);
    eglSwapBuffers(state->display, state->egl_surface);
}

bool tickApp(AndroidGhosttySurface* state) {
    if (state == nullptr || state->app == nullptr) {
        return false;
    }
    state->rendered_during_tick = false;
    ghostty_app_tick(state->app);
    return state->rendered_during_tick;
}

void applyFontSizeAction(AndroidGhosttySurface* state, ghostty_config_t config) {
    if (state == nullptr || state->surface == nullptr || config == nullptr) {
        return;
    }

    float font_size = 0.0f;
    if (!ghostty_config_get(config, &font_size, "font-size", sizeof("font-size") - 1)) {
        return;
    }

    char action[64];
    const int action_len = std::snprintf(
        action,
        sizeof(action),
        "set_font_size:%g",
        static_cast<double>(font_size)
    );
    if (action_len <= 0 || static_cast<size_t>(action_len) >= sizeof(action)) {
        return;
    }

    ghostty_surface_binding_action(
        state->surface,
        action,
        static_cast<uintptr_t>(action_len)
    );
}

struct AttachedEnv {
    JNIEnv* env = nullptr;
    bool attached = false;
};

AttachedEnv attachJniEnv() {
    AttachedEnv result;
    if (g_jvm == nullptr) {
        return result;
    }
    jint status = g_jvm->GetEnv(reinterpret_cast<void**>(&result.env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&result.env, nullptr) == JNI_OK) {
            result.attached = true;
        } else {
            result.env = nullptr;
        }
    } else if (status != JNI_OK) {
        result.env = nullptr;
    }
    return result;
}

void detachJniEnv(const AttachedEnv& attached) {
    if (attached.attached && g_jvm != nullptr) {
        g_jvm->DetachCurrentThread();
    }
}

void releaseGlobalRefs(AndroidGhosttySurface* state) {
    if (state == nullptr) {
        return;
    }
    if (state->input_callback == nullptr && state->wakeup_listener == nullptr) {
        return;
    }
    AttachedEnv attached = attachJniEnv();
    if (attached.env != nullptr) {
        if (state->input_callback != nullptr) {
            attached.env->DeleteGlobalRef(state->input_callback);
        }
        if (state->wakeup_listener != nullptr) {
            attached.env->DeleteGlobalRef(state->wakeup_listener);
        }
    }
    state->input_callback = nullptr;
    state->input_callback_method = nullptr;
    state->wakeup_listener = nullptr;
    state->wakeup_listener_method = nullptr;
    detachJniEnv(attached);
}

void destroyState(AndroidGhosttySurface* state) {
    if (state == nullptr) {
        return;
    }
    releaseGlobalRefs(state);
    if (state->surface != nullptr) {
        ghostty_surface_free(state->surface);
        state->surface = nullptr;
    }
    if (state->app != nullptr) {
        ghostty_app_free(state->app);
        state->app = nullptr;
    }
    if (state->config != nullptr) {
        ghostty_config_free(state->config);
        state->config = nullptr;
    }
    destroyEgl(state);
    if (state->window != nullptr) {
        ANativeWindow_release(state->window);
        state->window = nullptr;
    }
    delete state;
}

void androidGhosttyWakeup(void* userdata) {
    AndroidGhosttySurface* state = static_cast<AndroidGhosttySurface*>(userdata);
    if (state == nullptr) {
        return;
    }
    if (state->wakeup_listener == nullptr || state->wakeup_listener_method == nullptr) {
        return;
    }
    AttachedEnv attached = attachJniEnv();
    if (attached.env == nullptr) {
        return;
    }
    attached.env->CallVoidMethod(state->wakeup_listener, state->wakeup_listener_method);
    if (attached.env->ExceptionCheck()) {
        attached.env->ExceptionDescribe();
        attached.env->ExceptionClear();
    }
    detachJniEnv(attached);
}

bool androidGhosttyAction(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action) {
    if (action.tag != GHOSTTY_ACTION_RENDER) {
        return false;
    }

    AndroidGhosttySurface* state = nullptr;
    if (target.tag == GHOSTTY_TARGET_SURFACE && target.target.surface != nullptr) {
        state = static_cast<AndroidGhosttySurface*>(
            ghostty_surface_userdata(target.target.surface)
        );
    }
    if (state == nullptr && app != nullptr) {
        state = static_cast<AndroidGhosttySurface*>(ghostty_app_userdata(app));
    }
    if (state == nullptr) {
        return false;
    }

    drawSurface(state);
    state->rendered_during_tick = true;
    return true;
}

bool androidGhosttyReadClipboard(void* userdata, ghostty_clipboard_e clipboard, void* request) {
    (void)userdata;
    (void)clipboard;
    (void)request;
    return false;
}

void androidGhosttyConfirmReadClipboard(
    void* userdata,
    const char* title,
    void* request,
    ghostty_clipboard_request_e request_type
) {
    (void)userdata;
    (void)title;
    (void)request;
    (void)request_type;
}

void androidGhosttyWriteClipboard(
    void* userdata,
    ghostty_clipboard_e clipboard,
    const ghostty_clipboard_content_s* contents,
    size_t count,
    bool confirm
) {
    (void)userdata;
    (void)clipboard;
    (void)contents;
    (void)count;
    (void)confirm;
}

void androidGhosttyCloseSurface(void* userdata, bool process_active) {
    (void)userdata;
    (void)process_active;
}

void androidGhosttyExternalWrite(void* userdata, const uint8_t* data, uintptr_t length) {
    AndroidGhosttySurface* state = static_cast<AndroidGhosttySurface*>(userdata);
    if (state == nullptr || data == nullptr || length == 0) {
        return;
    }
    if (state->input_callback == nullptr || state->input_callback_method == nullptr) {
        return;
    }
    AttachedEnv attached = attachJniEnv();
    if (attached.env == nullptr) {
        return;
    }

    if (!state->input_logged_once.exchange(true)) {
        __android_log_print(
            ANDROID_LOG_INFO,
            kLogTag,
            "external_pty_write: first invocation (length=%zu, attached=%d)",
            static_cast<size_t>(length),
            attached.attached ? 1 : 0
        );
    }

    jbyteArray buffer = attached.env->NewByteArray(static_cast<jsize>(length));
    if (buffer != nullptr) {
        attached.env->SetByteArrayRegion(
            buffer,
            0,
            static_cast<jsize>(length),
            reinterpret_cast<const jbyte*>(data)
        );
        attached.env->CallVoidMethod(state->input_callback, state->input_callback_method, buffer);
        if (attached.env->ExceptionCheck()) {
            attached.env->ExceptionDescribe();
            attached.env->ExceptionClear();
        }
        attached.env->DeleteLocalRef(buffer);
    } else if (attached.env->ExceptionCheck()) {
        attached.env->ExceptionDescribe();
        attached.env->ExceptionClear();
    }

    detachJniEnv(attached);
}

} // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* /* reserved */) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeGhosttyVersion(
    JNIEnv* env,
    jobject /* thiz */
) {
    const ghostty_info_s info = ghostty_info();
    if (info.version == nullptr || info.version_len == 0) {
        return env->NewStringUTF("");
    }

    const std::string version(info.version, info.version + info.version_len);
    return env->NewStringUTF(version.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeCanCreateAndroidSurface(
    JNIEnv* /* env */,
    jobject /* thiz */
) {
    return ensureGhosttyInitialized() == GHOSTTY_SUCCESS && canCreateEglDisplay()
        ? JNI_TRUE
        : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeCreateAndroidSurface(
    JNIEnv* env,
    jobject /* thiz */,
    jobject surface,
    jint width,
    jint height,
    jfloat scale,
    jfloat font_size
) {
    if (surface == nullptr) {
        return 0;
    }
    if (ensureGhosttyInitialized() != GHOSTTY_SUCCESS) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "ghostty_init failed");
        return 0;
    }

    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    if (window == nullptr) {
        return 0;
    }

    AndroidGhosttySurface* state = new AndroidGhosttySurface();
    state->window = window;
    state->width = static_cast<uint32_t>(width > 0 ? width : 1);
    state->height = static_cast<uint32_t>(height > 0 ? height : 1);
    state->scale = scale > 0.0f ? scale : 1.0f;

    if (!createEgl(state)) {
        destroyState(state);
        return 0;
    }

    state->config = ghostty_config_new();
    if (state->config == nullptr) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "ghostty_config_new failed");
        destroyState(state);
        return 0;
    }
    ghostty_config_finalize(state->config);

    ghostty_runtime_config_s runtimeConfig = {};
    runtimeConfig.userdata = state;
    runtimeConfig.supports_selection_clipboard = false;
    runtimeConfig.wakeup_cb = androidGhosttyWakeup;
    runtimeConfig.action_cb = androidGhosttyAction;
    runtimeConfig.read_clipboard_cb = androidGhosttyReadClipboard;
    runtimeConfig.confirm_read_clipboard_cb = androidGhosttyConfirmReadClipboard;
    runtimeConfig.write_clipboard_cb = androidGhosttyWriteClipboard;
    runtimeConfig.close_surface_cb = androidGhosttyCloseSurface;

    state->app = ghostty_app_new(&runtimeConfig, state->config);
    if (state->app == nullptr) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "ghostty_app_new failed");
        destroyState(state);
        return 0;
    }

    ghostty_surface_config_s surfaceConfig = ghostty_surface_config_new();
    surfaceConfig.platform_tag = GHOSTTY_PLATFORM_ANDROID;
    surfaceConfig.platform.android.native_window = state->window;
    surfaceConfig.userdata = state;
    surfaceConfig.scale_factor = state->scale;
    surfaceConfig.font_size = font_size > 0.0f ? font_size : 13.0f;
    surfaceConfig.external_pty = true;
    surfaceConfig.external_pty_write = androidGhosttyExternalWrite;
    surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW;

    state->surface = ghostty_surface_new(state->app, &surfaceConfig);
    if (state->surface == nullptr) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "ghostty_surface_new failed");
        destroyState(state);
        return 0;
    }

    ghostty_app_set_focus(state->app, true);
    ghostty_surface_set_focus(state->surface, true);
    ghostty_surface_set_content_scale(state->surface, state->scale, state->scale);
    ghostty_surface_set_size(state->surface, state->width, state->height);
    ghostty_surface_refresh(state->surface);
    return reinterpret_cast<jlong>(state);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeDestroyAndroidSurface(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    destroyState(state);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeResizeAndroidSurface(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle,
    jint width,
    jint height,
    jfloat scale
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return;
    }
    state->width = static_cast<uint32_t>(width > 0 ? width : 1);
    state->height = static_cast<uint32_t>(height > 0 ? height : 1);
    state->scale = scale > 0.0f ? scale : 1.0f;
    if (!makeCurrent(state)) {
        return;
    }
    ghostty_surface_set_content_scale(state->surface, state->scale, state->scale);
    ghostty_surface_set_size(
        state->surface,
        state->width,
        state->height
    );
    ghostty_surface_refresh(state->surface);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeDrawAndroidSurface(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return;
    }
    drawSurface(state);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeTickAndroidSurface(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    return tickApp(state) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeWriteAndroidSurface(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jbyteArray data
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr || data == nullptr) {
        return;
    }

    const jsize len = env->GetArrayLength(data);
    jboolean is_copy = JNI_FALSE;
    jbyte* bytes = env->GetByteArrayElements(data, &is_copy);
    if (bytes == nullptr) {
        return;
    }
    ghostty_surface_write(
        state->surface,
        reinterpret_cast<const uint8_t*>(bytes),
        static_cast<uintptr_t>(len)
    );
    env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSetInputCallback(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jobject callback
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr) {
        return;
    }

    if (state->input_callback != nullptr) {
        env->DeleteGlobalRef(state->input_callback);
        state->input_callback = nullptr;
        state->input_callback_method = nullptr;
    }

    if (callback == nullptr) {
        return;
    }

    jobject global = env->NewGlobalRef(callback);
    if (global == nullptr) {
        return;
    }
    jclass cls = env->GetObjectClass(global);
    if (cls == nullptr) {
        env->DeleteGlobalRef(global);
        return;
    }
    jmethodID method = env->GetMethodID(cls, "onInput", "([B)V");
    env->DeleteLocalRef(cls);
    if (method == nullptr) {
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        env->DeleteGlobalRef(global);
        return;
    }
    state->input_callback = global;
    state->input_callback_method = method;
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSetWakeupListener(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jobject listener
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr) {
        return;
    }

    if (state->wakeup_listener != nullptr) {
        env->DeleteGlobalRef(state->wakeup_listener);
        state->wakeup_listener = nullptr;
        state->wakeup_listener_method = nullptr;
    }

    if (listener == nullptr) {
        return;
    }

    jobject global = env->NewGlobalRef(listener);
    if (global == nullptr) {
        return;
    }
    jclass cls = env->GetObjectClass(global);
    if (cls == nullptr) {
        env->DeleteGlobalRef(global);
        return;
    }
    jmethodID method = env->GetMethodID(cls, "onWakeup", "()V");
    env->DeleteLocalRef(cls);
    if (method == nullptr) {
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        env->DeleteGlobalRef(global);
        return;
    }
    state->wakeup_listener = global;
    state->wakeup_listener_method = method;
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSetOcclusion(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle,
    jboolean occluded
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return;
    }
    ghostty_surface_set_occlusion(state->surface, occluded == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSetFocus(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle,
    jboolean focused
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr) {
        return;
    }
    if (state->app != nullptr) {
        ghostty_app_set_focus(state->app, focused == JNI_TRUE);
    }
    if (state->surface != nullptr) {
        ghostty_surface_set_focus(state->surface, focused == JNI_TRUE);
    }
}

// Mirrors LitterGhosttyKey on iOS. Both surfaces map their platform key
// codes to this stable bridge enum, and the JNI / Obj-C bridges do the
// final translation to ghostty_input_key_e so a Ghostty header bump
// doesn't ripple into platform code.
enum class LitterBridgeKey : int {
    Unidentified = 0,
    Enter,
    Tab,
    Backspace,
    Escape,
    Space,
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    PageUp,
    PageDown,
    Home,
    End,
    Delete,
    Insert,
};

static ghostty_input_key_e bridgeKeyToGhosttyKey(LitterBridgeKey key) {
    switch (key) {
        case LitterBridgeKey::Enter:      return GHOSTTY_KEY_ENTER;
        case LitterBridgeKey::Tab:        return GHOSTTY_KEY_TAB;
        case LitterBridgeKey::Backspace:  return GHOSTTY_KEY_BACKSPACE;
        case LitterBridgeKey::Escape:     return GHOSTTY_KEY_ESCAPE;
        case LitterBridgeKey::Space:      return GHOSTTY_KEY_SPACE;
        case LitterBridgeKey::ArrowUp:    return GHOSTTY_KEY_ARROW_UP;
        case LitterBridgeKey::ArrowDown:  return GHOSTTY_KEY_ARROW_DOWN;
        case LitterBridgeKey::ArrowLeft:  return GHOSTTY_KEY_ARROW_LEFT;
        case LitterBridgeKey::ArrowRight: return GHOSTTY_KEY_ARROW_RIGHT;
        case LitterBridgeKey::PageUp:     return GHOSTTY_KEY_PAGE_UP;
        case LitterBridgeKey::PageDown:   return GHOSTTY_KEY_PAGE_DOWN;
        case LitterBridgeKey::Home:       return GHOSTTY_KEY_HOME;
        case LitterBridgeKey::End:        return GHOSTTY_KEY_END;
        case LitterBridgeKey::Delete:     return GHOSTTY_KEY_DELETE;
        case LitterBridgeKey::Insert:     return GHOSTTY_KEY_INSERT;
        case LitterBridgeKey::Unidentified:
        default:                          return GHOSTTY_KEY_UNIDENTIFIED;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSendKey(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jint action,
    jint key,
    jint mods,
    jstring text,
    jboolean composing
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return JNI_FALSE;
    }
    ghostty_input_key_s event = {};
    event.action = static_cast<ghostty_input_action_e>(action);
    event.mods = static_cast<ghostty_input_mods_e>(mods);
    event.consumed_mods = static_cast<ghostty_input_mods_e>(0);
    event.keycode = static_cast<uint32_t>(
        bridgeKeyToGhosttyKey(static_cast<LitterBridgeKey>(key))
    );
    const char* text_cstr = nullptr;
    if (text != nullptr) {
        text_cstr = env->GetStringUTFChars(text, nullptr);
    }
    event.text = text_cstr;
    event.unshifted_codepoint = 0;
    event.composing = composing == JNI_TRUE;
    bool consumed = ghostty_surface_key(state->surface, event);
    if (text_cstr != nullptr) {
        env->ReleaseStringUTFChars(text, text_cstr);
    }
    return consumed ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSendText(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jstring text
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr || text == nullptr) {
        return;
    }
    const char* cstr = env->GetStringUTFChars(text, nullptr);
    if (cstr == nullptr) {
        return;
    }
    ghostty_surface_text(state->surface, cstr, static_cast<uintptr_t>(strlen(cstr)));
    env->ReleaseStringUTFChars(text, cstr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSendPreedit(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jstring text
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return;
    }
    if (text == nullptr) {
        ghostty_surface_preedit(state->surface, nullptr, 0);
        return;
    }
    const char* cstr = env->GetStringUTFChars(text, nullptr);
    if (cstr == nullptr) {
        return;
    }
    ghostty_surface_preedit(state->surface, cstr, static_cast<uintptr_t>(strlen(cstr)));
    env->ReleaseStringUTFChars(text, cstr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeKeyboardChanged(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->app == nullptr) {
        return;
    }
    ghostty_app_keyboard_changed(state->app);
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeMouseMove(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle,
    jdouble x,
    jdouble y,
    jint mods
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return;
    }
    ghostty_surface_mouse_pos(state->surface, x, y, static_cast<ghostty_input_mods_e>(mods));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeMouseButton(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle,
    jboolean pressed,
    jint button,
    jint mods
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return JNI_FALSE;
    }
    bool consumed = ghostty_surface_mouse_button(
        state->surface,
        pressed == JNI_TRUE ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE,
        static_cast<ghostty_input_mouse_button_e>(button),
        static_cast<ghostty_input_mods_e>(mods)
    );
    return consumed ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeMouseCaptured(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return JNI_FALSE;
    }
    return ghostty_surface_mouse_captured(state->surface) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeMouseScroll(
    JNIEnv* /* env */,
    jobject /* thiz */,
    jlong handle,
    jdouble x,
    jdouble y,
    jboolean precise,
    jint mods
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return;
    }
    (void)mods;
    ghostty_input_scroll_mods_t scroll_mods = (precise == JNI_TRUE) ? 1 : 0;
    ghostty_surface_mouse_scroll(state->surface, x, y, scroll_mods);
}

/// Read live Ghostty surface metrics. Returns a 6-element `int[]` packed
/// as `{ columns, rows, width_px, height_px, cell_width_px, cell_height_px }`.
/// Returns an all-zero array when the surface isn't ready.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeSurfaceSize(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle
) {
    jintArray result = env->NewIntArray(6);
    if (result == nullptr) {
        return nullptr;
    }
    jint zeros[6] = {0, 0, 0, 0, 0, 0};
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        env->SetIntArrayRegion(result, 0, 6, zeros);
        return result;
    }
    ghostty_surface_size_s size = ghostty_surface_size(state->surface);
    jint values[6] = {
        (jint)size.columns,
        (jint)size.rows,
        (jint)size.width_px,
        (jint)size.height_px,
        (jint)size.cell_width_px,
        (jint)size.cell_height_px,
    };
    env->SetIntArrayRegion(result, 0, 6, values);
    return result;
}

/// Read text from a viewport-relative cell range. Returns `nil` if the
/// surface isn't ready, the range is empty, or the Ghostty call fails.
extern "C" JNIEXPORT jstring JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeReadText(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jint startRow,
    jint startCol,
    jint endRow,
    jint endCol
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->surface == nullptr) {
        return nullptr;
    }
    ghostty_selection_s selection = {};
    selection.top_left.tag = GHOSTTY_POINT_VIEWPORT;
    selection.top_left.coord = GHOSTTY_POINT_COORD_EXACT;
    selection.top_left.x = (uint32_t)startCol;
    selection.top_left.y = (uint32_t)startRow;
    selection.bottom_right.tag = GHOSTTY_POINT_VIEWPORT;
    selection.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT;
    selection.bottom_right.x = (uint32_t)endCol;
    selection.bottom_right.y = (uint32_t)endRow;
    selection.rectangle = false;

    ghostty_text_s text = {};
    if (!ghostty_surface_read_text(state->surface, selection, &text)) {
        return nullptr;
    }
    jstring result = nullptr;
    if (text.text != nullptr && text.text_len > 0) {
        // Ghostty hands us a UTF-8 buffer that is NOT NUL-terminated. Copy
        // it into a temporary owned buffer so we can hand a valid C string
        // to NewStringUTF.
        std::string owned(text.text, text.text_len);
        result = env->NewStringUTF(owned.c_str());
    }
    ghostty_surface_free_text(state->surface, &text);
    return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_litter_android_core_bridge_GhosttyRendererBridge_nativeApplyConfig(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle,
    jstring path
) {
    AndroidGhosttySurface* state = fromHandle(handle);
    if (state == nullptr || state->app == nullptr || state->surface == nullptr) {
        return JNI_FALSE;
    }
    if (path == nullptr) {
        return JNI_FALSE;
    }
    const char* path_cstr = env->GetStringUTFChars(path, nullptr);
    if (path_cstr == nullptr) {
        return JNI_FALSE;
    }
    ghostty_config_t config = ghostty_config_new();
    if (config == nullptr) {
        env->ReleaseStringUTFChars(path, path_cstr);
        return JNI_FALSE;
    }
    ghostty_config_load_file(config, path_cstr);
    ghostty_config_finalize(config);
    if (!makeCurrent(state)) {
        ghostty_config_free(config);
        env->ReleaseStringUTFChars(path, path_cstr);
        return JNI_FALSE;
    }
    ghostty_app_update_config(state->app, config);
    ghostty_surface_update_config(state->surface, config);
    applyFontSizeAction(state, config);
    ghostty_surface_set_content_scale(state->surface, state->scale, state->scale);
    ghostty_surface_set_size(state->surface, state->width, state->height);
    ghostty_surface_render(state->surface);
    eglSwapBuffers(state->display, state->egl_surface);
    ghostty_config_free(config);
    env->ReleaseStringUTFChars(path, path_cstr);
    return JNI_TRUE;
}
