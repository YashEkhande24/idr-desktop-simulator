#include "native_renderer.hpp"
#include <android/log.h>
#include <cmath>
#include <vector>
#include <string>
#include <algorithm>
#include <cstdio>

#define LOG_TAG "IDR_Renderer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace idr {

static const char* VERTEX_SHADER = R"(
    attribute vec2 aPosition;
    uniform vec2 uScale;
    uniform vec2 uOffset;
    void main() {
        gl_Position = vec4(aPosition * uScale + uOffset, 0.0, 1.0);
    }
)";

static const char* FRAGMENT_SHADER = R"(
    precision mediump float;
    uniform vec4 uColor;
    void main() {
        gl_FragColor = uColor;
    }
)";

static GLuint compileShader(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static GLuint createProgram(const char* vSrc, const char* fSrc) {
    GLuint vs = compileShader(GL_VERTEX_SHADER, vSrc);
    GLuint fs = compileShader(GL_FRAGMENT_SHADER, fSrc);
    if (!vs || !fs) return 0;
    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);
    return program;
}

NativeRenderer::NativeRenderer() {}

NativeRenderer::~NativeRenderer() {
    destroy();
}

bool NativeRenderer::init(ANativeWindow* window) {
    display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display_ == EGL_NO_DISPLAY) return false;

    eglInitialize(display_, nullptr, nullptr);

    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_BLUE_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_RED_SIZE, 8,
        EGL_NONE
    };

    EGLConfig config;
    EGLint numConfigs = 0;
    eglChooseConfig(display_, attribs, &config, 1, &numConfigs);
    if (numConfigs <= 0) {
        LOGE("Failed to find compatible EGLConfig!");
        return false;
    }

    EGLint format = 0;
    eglGetConfigAttrib(display_, config, EGL_NATIVE_VISUAL_ID, &format);
    ANativeWindow_setBuffersGeometry(window, 0, 0, format);

    surface_ = eglCreateWindowSurface(display_, config, window, nullptr);
    if (surface_ == EGL_NO_SURFACE) {
        LOGE("Failed eglCreateWindowSurface!");
        return false;
    }

    const EGLint contextAttribs2[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    context_ = eglCreateContext(display_, config, EGL_NO_CONTEXT, contextAttribs2);
    if (context_ == EGL_NO_CONTEXT) {
        LOGE("Failed eglCreateContext!");
        return false;
    }

    if (eglMakeCurrent(display_, surface_, surface_, context_) == EGL_FALSE) {
        LOGE("Failed eglMakeCurrent!");
        return false;
    }

    eglQuerySurface(display_, surface_, EGL_WIDTH, &width_);
    eglQuerySurface(display_, surface_, EGL_HEIGHT, &height_);

    glViewport(0, 0, width_, height_);

    initShaders();
    LOGI("Native OpenGL ES 2.0 renderer initialized successfully (%dx%d)", width_, height_);
    return true;
}

void NativeRenderer::initShaders() {
    lineProgram_ = createProgram(VERTEX_SHADER, FRAGMENT_SHADER);
    uScale_    = glGetUniformLocation(lineProgram_, "uScale");
    uOffset_   = glGetUniformLocation(lineProgram_, "uOffset");
    uColor_    = glGetUniformLocation(lineProgram_, "uColor");
    aPosition_ = glGetAttribLocation(lineProgram_, "aPosition");
}

void NativeRenderer::drawRect(float x1, float y1, float x2, float y2, float r, float g, float b, float a) {
    float verts[] = {
        x1, y1,   x2, y1,   x2, y2,
        x1, y1,   x2, y2,   x1, y2
    };
    glUniform2f(uScale_, 1.0f, 1.0f);
    glUniform2f(uOffset_, 0.0f, 0.0f);
    glUniform4f(uColor_, r, g, b, a);

    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, verts);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(aPosition_);
}

void NativeRenderer::drawRectOutline(float x1, float y1, float x2, float y2, float r, float g, float b, float a, float lineWidth) {
    float verts[] = {
        x1, y1,   x2, y1,
        x2, y1,   x2, y2,
        x2, y2,   x1, y2,
        x1, y2,   x1, y1
    };
    glUniform2f(uScale_, 1.0f, 1.0f);
    glUniform2f(uOffset_, 0.0f, 0.0f);
    glUniform4f(uColor_, r, g, b, a);

    glLineWidth(lineWidth);
    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, verts);
    glDrawArrays(GL_LINES, 0, 8);
    glDisableVertexAttribArray(aPosition_);
}

void NativeRenderer::drawCircle(float cx, float cy, float radius, float r, float g, float b, float a, int segments) {
    float aspect = (height_ > 0) ? (static_cast<float>(width_) / height_) : 0.5f;
    std::vector<float> verts;
    verts.reserve(segments * 2);

    for (int i = 0; i <= segments; ++i) {
        float theta = (2.0f * 3.14159265f * i) / segments;
        float x = cx + radius * std::cos(theta) * aspect;
        float y = cy + radius * std::sin(theta);
        verts.push_back(x);
        verts.push_back(y);
    }

    glUniform2f(uScale_, 1.0f, 1.0f);
    glUniform2f(uOffset_, 0.0f, 0.0f);
    glUniform4f(uColor_, r, g, b, a);

    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, verts.data());
    glDrawArrays(GL_LINE_STRIP, 0, static_cast<GLsizei>(verts.size() / 2));
    glDisableVertexAttribArray(aPosition_);
}

void NativeRenderer::drawText(float x, float y, float scale, const std::string& text, float r, float g, float b, float a) {
    float aspect = (height_ > 0) ? (static_cast<float>(width_) / height_) : 0.5f;
    float cw = scale * aspect;
    float ch = scale * 1.6f;
    float curX = x;

    std::vector<float> verts;

    auto addLine = [&](float x1, float y1, float x2, float y2) {
        verts.push_back(curX + x1 * cw);
        verts.push_back(y + y1 * ch);
        verts.push_back(curX + x2 * cw);
        verts.push_back(y + y2 * ch);
    };

    for (char ch_in : text) {
        char c = (ch_in >= 'a' && ch_in <= 'z') ? (ch_in - 'a' + 'A') : ch_in;

        switch (c) {
            case '0':
                addLine(0,0, 1,0); addLine(1,0, 1,1); addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0,0, 1,1);
                break;
            case '1':
                addLine(0.5f,0, 0.5f,1); addLine(0.2f,0.8f, 0.5f,1); addLine(0.2f,0, 0.8f,0);
                break;
            case '2':
                addLine(0,1, 1,1); addLine(1,1, 1,0.5f); addLine(1,0.5f, 0,0.5f); addLine(0,0.5f, 0,0); addLine(0,0, 1,0);
                break;
            case '3':
                addLine(0,1, 1,1); addLine(1,1, 1,0); addLine(1,0, 0,0); addLine(0,0.5f, 1,0.5f);
                break;
            case '4':
                addLine(0,1, 0,0.5f); addLine(0,0.5f, 1,0.5f); addLine(1,1, 1,0);
                break;
            case '5':
                addLine(1,1, 0,1); addLine(0,1, 0,0.5f); addLine(0,0.5f, 1,0.5f); addLine(1,0.5f, 1,0); addLine(1,0, 0,0);
                break;
            case '6':
                addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0,0, 1,0); addLine(1,0, 1,0.5f); addLine(1,0.5f, 0,0.5f);
                break;
            case '7':
                addLine(0,1, 1,1); addLine(1,1, 0.3f,0);
                break;
            case '8':
                addLine(0,0, 1,0); addLine(1,0, 1,1); addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0,0.5f, 1,0.5f);
                break;
            case '9':
                addLine(0,0, 1,0); addLine(1,0, 1,1); addLine(1,1, 0,1); addLine(0,1, 0,0.5f); addLine(0,0.5f, 1,0.5f);
                break;
            case '.':
                addLine(0.4f,0, 0.6f,0); addLine(0.5f,-0.1f, 0.5f,0.1f);
                break;
            case ':':
                addLine(0.5f,0.25f, 0.5f,0.30f); addLine(0.5f,0.70f, 0.5f,0.75f);
                break;
            case '-':
                addLine(0.2f,0.5f, 0.8f,0.5f);
                break;
            case '+':
                addLine(0.2f,0.5f, 0.8f,0.5f); addLine(0.5f,0.2f, 0.5f,0.8f);
                break;
            case '/':
                addLine(0.1f,0, 0.9f,1);
                break;
            case '|':
                addLine(0.5f,0, 0.5f,1);
                break;
            case '[':
                addLine(0.6f,1, 0.2f,1); addLine(0.2f,1, 0.2f,0); addLine(0.2f,0, 0.6f,0);
                break;
            case ']':
                addLine(0.2f,1, 0.6f,1); addLine(0.6f,1, 0.6f,0); addLine(0.6f,0, 0.2f,0);
                break;
            case '<':
                addLine(0.8f,0.9f, 0.2f,0.5f); addLine(0.2f,0.5f, 0.8f,0.1f);
                break;
            case '>':
                addLine(0.2f,0.9f, 0.8f,0.5f); addLine(0.8f,0.5f, 0.2f,0.1f);
                break;
            case '%':
                addLine(0,0, 1,1); addLine(0.1f,0.8f, 0.3f,0.8f); addLine(0.7f,0.2f, 0.9f,0.2f);
                break;
            case 'A':
                addLine(0,0, 0.5f,1); addLine(0.5f,1, 1,0); addLine(0.25f,0.45f, 0.75f,0.45f);
                break;
            case 'B':
                addLine(0,0, 0,1); addLine(0,1, 0.7f,1); addLine(0.7f,1, 0.7f,0.5f); addLine(0.7f,0.5f, 0,0.5f); addLine(0.7f,0.5f, 0.7f,0); addLine(0.7f,0, 0,0);
                break;
            case 'C':
                addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0,0, 1,0);
                break;
            case 'D':
                addLine(0,0, 0,1); addLine(0,1, 0.7f,1); addLine(0.7f,1, 1,0.7f); addLine(1,0.7f, 1,0.3f); addLine(1,0.3f, 0.7f,0); addLine(0.7f,0, 0,0);
                break;
            case 'E':
                addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0,0, 1,0); addLine(0,0.5f, 0.7f,0.5f);
                break;
            case 'F':
                addLine(0,0, 0,1); addLine(0,1, 1,1); addLine(0,0.5f, 0.7f,0.5f);
                break;
            case 'G':
                addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0,0, 1,0); addLine(1,0, 1,0.5f); addLine(1,0.5f, 0.5f,0.5f);
                break;
            case 'H':
                addLine(0,0, 0,1); addLine(1,0, 1,1); addLine(0,0.5f, 1,0.5f);
                break;
            case 'I':
                addLine(0.5f,0, 0.5f,1); addLine(0.2f,1, 0.8f,1); addLine(0.2f,0, 0.8f,0);
                break;
            case 'J':
                addLine(0.2f,0.3f, 0.4f,0); addLine(0.4f,0, 0.7f,0); addLine(0.7f,0, 0.7f,1);
                break;
            case 'K':
                addLine(0,0, 0,1); addLine(1,1, 0,0.5f); addLine(0,0.5f, 1,0);
                break;
            case 'L':
                addLine(0,1, 0,0); addLine(0,0, 0.9f,0);
                break;
            case 'M':
                addLine(0,0, 0,1); addLine(0,1, 0.5f,0.5f); addLine(0.5f,0.5f, 1,1); addLine(1,1, 1,0);
                break;
            case 'N':
                addLine(0,0, 0,1); addLine(0,1, 1,0); addLine(1,0, 1,1);
                break;
            case 'O':
                addLine(0,0, 1,0); addLine(1,0, 1,1); addLine(1,1, 0,1); addLine(0,1, 0,0);
                break;
            case 'P':
                addLine(0,0, 0,1); addLine(0,1, 1,1); addLine(1,1, 1,0.5f); addLine(1,0.5f, 0,0.5f);
                break;
            case 'Q':
                addLine(0,0, 1,0); addLine(1,0, 1,1); addLine(1,1, 0,1); addLine(0,1, 0,0); addLine(0.6f,0.3f, 1.0f,-0.1f);
                break;
            case 'R':
                addLine(0,0, 0,1); addLine(0,1, 1,1); addLine(1,1, 1,0.5f); addLine(1,0.5f, 0,0.5f); addLine(0.5f,0.5f, 1,0);
                break;
            case 'S':
                addLine(1,1, 0,1); addLine(0,1, 0,0.5f); addLine(0,0.5f, 1,0.5f); addLine(1,0.5f, 1,0); addLine(1,0, 0,0);
                break;
            case 'T':
                addLine(0.5f,0, 0.5f,1); addLine(0,1, 1,1);
                break;
            case 'U':
                addLine(0,1, 0,0); addLine(0,0, 1,0); addLine(1,0, 1,1);
                break;
            case 'V':
                addLine(0,1, 0.5f,0); addLine(0.5f,0, 1,1);
                break;
            case 'W':
                addLine(0,1, 0.2f,0); addLine(0.2f,0, 0.5f,0.6f); addLine(0.5f,0.6f, 0.8f,0); addLine(0.8f,0, 1,1);
                break;
            case 'X':
                addLine(0,0, 1,1); addLine(0,1, 1,0);
                break;
            case 'Y':
                addLine(0,1, 0.5f,0.5f); addLine(1,1, 0.5f,0.5f); addLine(0.5f,0.5f, 0.5f,0);
                break;
            case 'Z':
                addLine(0,1, 1,1); addLine(1,1, 0,0); addLine(0,0, 1,0);
                break;
            default:
                break;
        }

        curX += cw * 1.35f;
    }

    if (!verts.empty()) {
        glUniform2f(uScale_, 1.0f, 1.0f);
        glUniform2f(uOffset_, 0.0f, 0.0f);
        glUniform4f(uColor_, r, g, b, a);

        glLineWidth(2.5f);
        glEnableVertexAttribArray(aPosition_);
        glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, verts.data());
        glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(verts.size() / 2));
        glDisableVertexAttribArray(aPosition_);
    }
}

void NativeRenderer::render(const NavSolution& solution) {
    if (display_ == EGL_NO_DISPLAY || surface_ == EGL_NO_SURFACE) return;

    animTimer_ += 0.02f;

    // Deep tech cockpit background (#070B12)
    glClearColor(0.027f, 0.043f, 0.070f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(lineProgram_);

    drawGrid();
    drawTrails(solution);
    drawCompassRose(0.0f, 0.15f, 0.38f, solution.headingDeg);
    drawSpeedometer(0.0f, 0.15f, solution.velocity.norm() * 3.6);
    drawHud(solution);

    eglSwapBuffers(display_, surface_);
}

void NativeRenderer::drawGrid() {
    float gridVerts[] = {
        -1.0f, -0.6f,  1.0f, -0.6f,
        -1.0f, -0.2f,  1.0f, -0.2f,
        -1.0f,  0.2f,  1.0f,  0.2f,
        -1.0f,  0.6f,  1.0f,  0.6f,
        -0.6f, -1.0f, -0.6f,  1.0f,
        -0.2f, -1.0f, -0.2f,  1.0f,
         0.2f, -1.0f,  0.2f,  1.0f,
         0.6f, -1.0f,  0.6f,  1.0f,
    };

    glUniform2f(uScale_, 1.0f, 1.0f);
    glUniform2f(uOffset_, 0.0f, 0.0f);
    glUniform4f(uColor_, 0.08f, 0.14f, 0.22f, 0.7f); // Clear visible neon grid

    glLineWidth(1.0f);
    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, gridVerts);
    glDrawArrays(GL_LINES, 0, 16);
    glDisableVertexAttribArray(aPosition_);
}

void NativeRenderer::drawCompassRose(float cx, float cy, float radius, double headingDeg) {
    float aspect = (height_ > 0) ? (static_cast<float>(width_) / height_) : 0.5f;

    // Glowing compass circles
    drawCircle(cx, cy, radius, 0.10f, 0.30f, 0.50f, 0.8f, 48);
    drawCircle(cx, cy, radius * 0.85f, 0.05f, 0.18f, 0.30f, 0.5f, 48);

    // Crosshairs
    float chLines[] = {
        cx - radius * 1.15f * aspect, cy,  cx + radius * 1.15f * aspect, cy,
        cx, cy - radius * 1.15f,           cx, cy + radius * 1.15f
    };
    glUniform2f(uScale_, 1.0f, 1.0f);
    glUniform2f(uOffset_, 0.0f, 0.0f);
    glUniform4f(uColor_, 0.12f, 0.28f, 0.45f, 0.7f);
    glLineWidth(1.5f);
    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, chLines);
    glDrawArrays(GL_LINES, 0, 4);
    glDisableVertexAttribArray(aPosition_);

    // Cardinal directions labels
    drawText(cx - 0.02f * aspect, cy + radius * 1.05f, 0.035f, "N", 0.0f, 1.0f, 0.5f);
    drawText(cx + radius * 1.05f * aspect, cy - 0.025f, 0.035f, "E", 0.4f, 0.7f, 1.0f);
    drawText(cx - 0.02f * aspect, cy - radius * 1.18f, 0.035f, "S", 0.4f, 0.7f, 1.0f);
    drawText(cx - radius * 1.18f * aspect, cy - 0.025f, 0.035f, "W", 0.4f, 0.7f, 1.0f);

    // Rotating heading needle
    double yawRad = (90.0 - headingDeg) * (3.14159265 / 180.0);
    float cyaw = static_cast<float>(std::cos(yawRad));
    float syaw = static_cast<float>(std::sin(yawRad));
    float needleLen = radius * 0.75f;

    float needleVerts[] = {
        cx, cy,  cx + needleLen * cyaw * aspect, cy + needleLen * syaw,
        cx, cy,  cx - needleLen * 0.3f * cyaw * aspect, cy - needleLen * 0.3f * syaw
    };

    glUniform4f(uColor_, 0.0f, 1.0f, 0.6f, 1.0f); // Bright emerald heading needle
    glLineWidth(4.0f);
    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, needleVerts);
    glDrawArrays(GL_LINES, 0, 4);
    glDisableVertexAttribArray(aPosition_);
}

void NativeRenderer::drawSpeedometer(float cx, float cy, double speedKmh) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.1f", speedKmh);
    drawText(cx - 0.15f, cy + 0.02f, 0.065f, buf, 0.0f, 0.90f, 1.0f);
    drawText(cx - 0.12f, cy - 0.08f, 0.030f, "KM/H", 0.4f, 0.75f, 1.0f);
}

void NativeRenderer::drawTrails(const NavSolution& solution) {
    idrTrail_.push_back(solution.positionEnu);
    if (idrTrail_.size() > 300) idrTrail_.pop_front();

    if (idrTrail_.size() < 2) return;

    // Scale 1 meter = 0.005 units
    glUniform2f(uScale_, 0.005f, 0.005f);
    glUniform2f(uOffset_, 0.0f, 0.15f);

    glUniform4f(uColor_, 0.0f, 0.90f, 1.0f, 1.0f);
    std::vector<float> pts;
    pts.reserve(idrTrail_.size() * 2);
    for (const auto& p : idrTrail_) {
        pts.push_back(static_cast<float>(p.x));
        pts.push_back(static_cast<float>(p.y));
    }

    glEnableVertexAttribArray(aPosition_);
    glVertexAttribPointer(aPosition_, 2, GL_FLOAT, GL_FALSE, 0, pts.data());
    glLineWidth(3.0f);
    glDrawArrays(GL_LINE_STRIP, 0, static_cast<GLsizei>(idrTrail_.size()));
    glDisableVertexAttribArray(aPosition_);
}

void NativeRenderer::drawHud(const NavSolution& solution) {
    char buf[128];

    // ==========================================
    // 1. TOP HEADER TITLE BAR
    // ==========================================
    drawRect(-0.95f, 0.96f, 0.95f, 0.86f, 0.04f, 0.08f, 0.15f, 0.95f);
    drawRectOutline(-0.95f, 0.96f, 0.95f, 0.86f, 0.0f, 0.85f, 1.0f, 1.0f, 2.0f);

    drawText(-0.85f, 0.91f, 0.028f, "PURE C++ IDR NAVIGATOR", 0.0f, 0.95f, 1.0f);
    drawText(-0.85f, 0.88f, 0.018f, "HARDWARE SENSORS | ZERO JAVA | NDK 27", 0.45f, 0.70f, 0.90f);

    // ==========================================
    // 2. STATUS BADGE
    // ==========================================
    if (solution.isOutage) {
        // Red Pulsing Outage Banner
        float pulse = 0.7f + 0.3f * std::sin(animTimer_ * 8.0f);
        drawRect(-0.95f, 0.84f, 0.95f, 0.75f, 0.40f * pulse, 0.05f, 0.05f, 0.95f);
        drawRectOutline(-0.95f, 0.84f, 0.95f, 0.75f, 1.0f, 0.2f, 0.2f, 1.0f, 3.0f);
        drawText(-0.75f, 0.785f, 0.026f, "[ STATUS: TUNNEL OUTAGE (SIMULATED) ]", 1.0f, 0.3f, 0.3f);
    } else {
        // Emerald Green Nominal Banner
        drawRect(-0.95f, 0.84f, 0.95f, 0.75f, 0.03f, 0.20f, 0.10f, 0.95f);
        drawRectOutline(-0.95f, 0.84f, 0.95f, 0.75f, 0.0f, 0.9f, 0.4f, 1.0f, 2.0f);
        drawText(-0.70f, 0.785f, 0.026f, "[ STATUS: OUTDOOR GNSS NOMINAL ]", 0.0f, 1.0f, 0.5f);
    }

    // ==========================================
    // 3. TELEMETRY CARDS (MIDDLE-LOWER SECTION)
    // ==========================================

    // Card A: Proposed IDR Drift
    drawRect(-0.95f, -0.32f, 0.95f, -0.42f, 0.04f, 0.09f, 0.16f, 0.90f);
    drawRectOutline(-0.95f, -0.32f, 0.95f, -0.42f, 0.0f, 0.85f, 1.0f, 0.9f, 1.5f);
    std::snprintf(buf, sizeof(buf), "PROPOSED IDR DRIFT: %.2F M", solution.idrDrift);
    drawText(-0.85f, -0.38f, 0.024f, buf, 0.0f, 0.95f, 1.0f);

    // Card B: Classic Dead Reckoning Drift
    drawRect(-0.95f, -0.44f, 0.95f, -0.54f, 0.12f, 0.07f, 0.03f, 0.90f);
    drawRectOutline(-0.95f, -0.44f, 0.95f, -0.54f, 1.0f, 0.60f, 0.0f, 0.9f, 1.5f);
    std::snprintf(buf, sizeof(buf), "CLASSIC DR DRIFT:   %.2F M", solution.classicDrift);
    drawText(-0.85f, -0.50f, 0.024f, buf, 1.0f, 0.65f, 0.1f);

    // Card C: Live Sensor Diagnostics (HDOP, Heading, Jerk)
    drawRect(-0.95f, -0.56f, 0.95f, -0.66f, 0.04f, 0.08f, 0.12f, 0.90f);
    drawRectOutline(-0.95f, -0.56f, 0.95f, -0.66f, 0.30f, 0.50f, 0.70f, 0.6f, 1.0f);
    std::snprintf(buf, sizeof(buf), "HDOP: %.2F | AZIMUTH: %03.0F DEG | ZUPT: %s",
                  solution.hdop, solution.headingDeg, solution.isStandstill ? "LOCK" : "DRIVE");
    drawText(-0.88f, -0.62f, 0.019f, buf, 0.4f, 0.8f, 0.9f);

    // ==========================================
    // 4. PROMINENT OUTAGE TOGGLE BUTTON (BOTTOM DOCK)
    // ==========================================
    if (solution.isOutage) {
        // Red glowing active button
        drawRect(-0.95f, -0.72f, 0.95f, -0.92f, 0.50f, 0.08f, 0.08f, 0.98f);
        drawRectOutline(-0.95f, -0.72f, 0.95f, -0.92f, 1.0f, 0.3f, 0.3f, 1.0f, 3.5f);
        drawText(-0.82f, -0.80f, 0.028f, ">>> TAP TO RESTORE GNSS <<<", 1.0f, 1.0f, 1.0f);
        drawText(-0.70f, -0.87f, 0.018f, "(WATCH CLASSIC DR DRIFT EXPLODE)", 1.0f, 0.7f, 0.7f);
    } else {
        // Glowing cyan/amber action button
        drawRect(-0.95f, -0.72f, 0.95f, -0.92f, 0.08f, 0.18f, 0.28f, 0.98f);
        drawRectOutline(-0.95f, -0.72f, 0.95f, -0.92f, 0.0f, 0.90f, 1.0f, 1.0f, 3.0f);
        drawText(-0.85f, -0.80f, 0.026f, ">>> TAP TO SIMULATE TUNNEL <<<", 0.0f, 1.0f, 0.6f);
        drawText(-0.70f, -0.87f, 0.018f, "(CUTS OFF OUTDOOR GNSS RECEPTION)", 0.5f, 0.8f, 1.0f);
    }
}

void NativeRenderer::destroy() {
    if (display_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (context_ != EGL_NO_CONTEXT) eglDestroyContext(display_, context_);
        if (surface_ != EGL_NO_SURFACE) eglDestroySurface(display_, surface_);
        eglTerminate(display_);
    }
    display_ = EGL_NO_DISPLAY;
    surface_ = EGL_NO_SURFACE;
    context_ = EGL_NO_CONTEXT;
}

} // namespace idr
