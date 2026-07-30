#include "android_video_bridge.hpp"

#include <SDL_log.h>

#include <algorithm>
#include <cmath>

namespace
{
	int renderScalePreset = AndroidVideo::DEFAULT_RENDER_SCALE;
	int nativeRenderScaleDepth = 0;
	int lastLoggedPreset = -1;
	int lastLoggedOutputWidth = -1;
	int lastLoggedOutputHeight = -1;
	int lastLoggedFrameRate = -1;
}

namespace AndroidVideo
{
	int sanitizeRenderScalePreset(const int preset)
	{
		switch (preset)
		{
			case RENDER_SCALE_NATIVE:
			case RENDER_SCALE_720P:
			case RENDER_SCALE_1080P:
				return preset;
			default:
				return DEFAULT_RENDER_SCALE;
		}
	}

	int sanitizeFrameRate(const int frameRate)
	{
		switch (frameRate)
		{
			case 60:
			case 90:
			case 120:
				return frameRate;
			default:
				return DEFAULT_FRAME_RATE;
		}
	}

	void setRenderScalePreset(const int preset)
	{
		renderScalePreset = sanitizeRenderScalePreset(preset);
	}

	int getRenderScalePreset()
	{
		return renderScalePreset;
	}

	const char* getRenderScalePresetName(const int preset)
	{
		switch (sanitizeRenderScalePreset(preset))
		{
			case RENDER_SCALE_NATIVE:
				return "native";
			case RENDER_SCALE_720P:
				return "720p";
			case RENDER_SCALE_1080P:
			default:
				return "1080p";
		}
	}

	RenderSize getRenderSize(
		const int viewportWidth,
		const int viewportHeight,
		const int outputWidth,
		const int outputHeight)
	{
		RenderSize result{
			std::max(1, viewportWidth),
			std::max(1, viewportHeight)
		};
		const int preset = sanitizeRenderScalePreset(renderScalePreset);
		const int outputShortEdge = std::min(outputWidth, outputHeight);
		if (nativeRenderScaleDepth > 0
			|| preset == RENDER_SCALE_NATIVE
			|| outputShortEdge <= 0
			|| outputShortEdge <= preset)
		{
			return result;
		}

		const double scale = static_cast<double>(preset)
			/ static_cast<double>(outputShortEdge);
		result.width = std::max(1, static_cast<int>(std::lround(viewportWidth * scale)));
		result.height = std::max(1, static_cast<int>(std::lround(viewportHeight * scale)));
		return result;
	}

	bool isRenderScaled(
		const int viewportWidth,
		const int viewportHeight,
		const int outputWidth,
		const int outputHeight)
	{
		const RenderSize size = getRenderSize(
			viewportWidth, viewportHeight, outputWidth, outputHeight);
		return size.width != viewportWidth || size.height != viewportHeight;
	}

	void logRenderPolicy(
		const int outputWidth,
		const int outputHeight,
		const int frameRate)
	{
		const int preset = sanitizeRenderScalePreset(renderScalePreset);
		if (lastLoggedPreset == preset
			&& lastLoggedOutputWidth == outputWidth
			&& lastLoggedOutputHeight == outputHeight
			&& lastLoggedFrameRate == frameRate)
		{
			return;
		}

		const RenderSize worldSize = getRenderSize(
			outputWidth, outputHeight, outputWidth, outputHeight);
		SDL_Log(
			"BARONY_ANDROID_RENDER_POLICY preset=%s output=%dx%d world=%dx%d fps=%d ui=native",
			getRenderScalePresetName(preset),
			outputWidth,
			outputHeight,
			worldSize.width,
			worldSize.height,
			frameRate);
		lastLoggedPreset = preset;
		lastLoggedOutputWidth = outputWidth;
		lastLoggedOutputHeight = outputHeight;
		lastLoggedFrameRate = frameRate;
	}

	ScopedNativeRenderScale::ScopedNativeRenderScale()
	{
		++nativeRenderScaleDepth;
	}

	ScopedNativeRenderScale::~ScopedNativeRenderScale()
	{
		nativeRenderScaleDepth = std::max(0, nativeRenderScaleDepth - 1);
	}
}
