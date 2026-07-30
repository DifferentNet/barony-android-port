#pragma once

namespace AndroidVideo
{
	constexpr int RENDER_SCALE_NATIVE = 0;
	constexpr int RENDER_SCALE_720P = 720;
	constexpr int RENDER_SCALE_1080P = 1080;
	constexpr int DEFAULT_RENDER_SCALE = RENDER_SCALE_1080P;
	constexpr int DEFAULT_FRAME_RATE = 60;

	struct RenderSize
	{
		int width;
		int height;
	};

	int sanitizeRenderScalePreset(int preset);
	int sanitizeFrameRate(int frameRate);
	void setRenderScalePreset(int preset);
	int getRenderScalePreset();
	const char* getRenderScalePresetName(int preset);
	RenderSize getRenderSize(
		int viewportWidth,
		int viewportHeight,
		int outputWidth,
		int outputHeight);
	bool isRenderScaled(
		int viewportWidth,
		int viewportHeight,
		int outputWidth,
		int outputHeight);
	void logRenderPolicy(int outputWidth, int outputHeight, int frameRate);

	class ScopedNativeRenderScale
	{
	public:
		ScopedNativeRenderScale();
		~ScopedNativeRenderScale();

		ScopedNativeRenderScale(const ScopedNativeRenderScale&) = delete;
		ScopedNativeRenderScale& operator=(const ScopedNativeRenderScale&) = delete;
	};
}
