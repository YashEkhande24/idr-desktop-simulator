#pragma once

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <android/native_window.h>
#include <deque>
#include <vector>
#include <string>
#include "idr/types.hpp"

namespace idr {

class NativeRenderer {
public:
    NativeRenderer();
    ~NativeRenderer();

    bool init(ANativeWindow* window);
    void render(const NavSolution& solution);
    void destroy();

    int width() const { return width_; }
    int height() const { return height_; }

    // Vector text rendering engine
    void drawText(float x, float y, float scale, const std::string& text, float r, float g, float b, float a = 1.0f);

private:
    void initShaders();
    void drawRect(float x1, float y1, float x2, float y2, float r, float g, float b, float a);
    void drawRectOutline(float x1, float y1, float x2, float y2, float r, float g, float b, float a, float lineWidth = 2.0f);
    void drawCircle(float cx, float cy, float radius, float r, float g, float b, float a, int segments = 36);
    void drawGrid();
    void drawCompassRose(float cx, float cy, float radius, double headingDeg);
    void drawSpeedometer(float cx, float cy, double speedKmh);
    void drawTrails(const NavSolution& solution);
    void drawHud(const NavSolution& solution);

    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLSurface surface_ = EGL_NO_SURFACE;
    EGLContext context_ = EGL_NO_CONTEXT;
    int width_ = 1080;
    int height_ = 2400;

    GLuint lineProgram_ = 0;
    GLint uScale_ = -1;
    GLint uOffset_ = -1;
    GLint uColor_ = -1;
    GLint aPosition_ = -1;

    std::deque<Vec3> idrTrail_;
    std::deque<Vec3> classicTrail_;
    float animTimer_ = 0.0f;
};

} // namespace idr
