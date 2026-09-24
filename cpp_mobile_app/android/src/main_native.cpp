#include <android/log.h>
#include <android_native_app_glue.h>
#include <chrono>
#include <thread>
#include "idr/pipeline.hpp"
#include "native_sensor_service.hpp"
#include "native_renderer.hpp"

#define LOG_TAG "IDR_NativeMain"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

struct AppState {
    android_app* app = nullptr;
    idr::IdrPipeline pipeline;
    idr::NativeSensorService* sensors = nullptr;
    idr::NativeRenderer* renderer = nullptr;
    bool animating = false;
};

static void handleCmd(android_app* app, int32_t cmd) {
    auto* s = static_cast<AppState*>(app->userData);
    switch (cmd) {
        case APP_CMD_INIT_WINDOW:
            if (app->window != nullptr) {
                s->renderer = new idr::NativeRenderer();
                s->renderer->init(app->window);

                s->sensors = new idr::NativeSensorService(s->pipeline);
                s->sensors->init(app->looper);

                s->animating = true;
                LOGI("Window initialized. Native rendering and sensors started.");
            }
            break;

        case APP_CMD_TERM_WINDOW:
            s->animating = false;
            if (s->sensors) {
                delete s->sensors;
                s->sensors = nullptr;
            }
            if (s->renderer) {
                delete s->renderer;
                s->renderer = nullptr;
            }
            LOGI("Window terminated. Cleaned up native resources.");
            break;

        case APP_CMD_GAINED_FOCUS:
            s->animating = true;
            break;

        case APP_CMD_LOST_FOCUS:
            s->animating = false;
            break;
    }
}

static int32_t handleInput(android_app* app, AInputEvent* event) {
    auto* s = static_cast<AppState*>(app->userData);
    if (AInputEvent_getType(event) == AINPUT_EVENT_TYPE_MOTION) {
        int32_t action = AMotionEvent_getAction(event) & AMOTION_EVENT_ACTION_MASK;
        if (action == AMOTION_EVENT_ACTION_UP) {
            float y = AMotionEvent_getY(event, 0);
            float h = s->renderer ? static_cast<float>(s->renderer->height()) : 1000.0f;
            // If tapped anywhere in bottom 30% of screen, toggle Tunnel Outage
            if (y > h * 0.70f) {
                s->pipeline.toggleTunnelOutage();
                LOGI("Toggled Tunnel Outage! Current: %s", s->pipeline.isTunnelOutage() ? "TUNNEL" : "NOMINAL");
                return 1;
            }
        }
    }
    return 0;
}

void android_main(struct android_app* state) {
    AppState appState;
    appState.app = state;
    state->userData = &appState;
    state->onAppCmd = handleCmd;
    state->onInputEvent = handleInput;

    LOGI("==================================================");
    LOGI("  IDR Pure C++ NativeActivity Started             ");
    LOGI("  100%% C++20, Zero Java, Zero Dart               ");
    LOGI("==================================================");

    while (true) {
        int ident;
        int events;
        android_poll_source* source;

        // Poll events without blocking if animating
        while ((ident = ALooper_pollOnce(appState.animating ? 0 : -1, nullptr, &events, reinterpret_cast<void**>(&source))) >= 0) {
            if (source != nullptr) {
                source->process(state, source);
            }
            if (ident == idr::NativeSensorService::SENSOR_LOOPER_ID) {
                if (appState.sensors) {
                    appState.sensors->pollEvents();
                }
            }
            if (state->destroyRequested != 0) {
                if (appState.sensors) delete appState.sensors;
                if (appState.renderer) delete appState.renderer;
                LOGI("Pure C++ IDR app exiting cleanly.");
                return;
            }
        }

        // Hardware sensor dispatch
        if (appState.sensors) {
            appState.sensors->pollEvents();
        }

        // Render at 60 FPS
        if (appState.animating && appState.renderer) {
            appState.renderer->render(appState.pipeline.solution());
            std::this_thread::sleep_for(std::chrono::milliseconds(16));
        }
    }
}
