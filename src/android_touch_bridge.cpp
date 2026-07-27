#include "android_touch_bridge.hpp"

#ifdef __ANDROID__

#include <jni.h>

#include <SDL.h>
#include <SDL_system.h>

void androidUpdateTouchLayoutMode(AndroidTouchLayoutMode mode)
{
	static int lastMode = -1;
	static bool failureLogged = false;
	const int requestedMode = static_cast<int>(mode);
	if ( requestedMode == lastMode )
	{
		return;
	}

	JNIEnv* env = static_cast<JNIEnv*>(SDL_AndroidGetJNIEnv());
	jobject activity = static_cast<jobject>(SDL_AndroidGetActivity());
	if ( !env || !activity )
	{
		if ( !failureLogged )
		{
			failureLogged = true;
			SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
				"BARONY_ANDROID_TOUCH_LAYOUT_FAILED stage=activity");
		}
		return;
	}

	jclass activityClass = env->GetObjectClass(activity);
	jmethodID setLayoutMethod = activityClass
		? env->GetMethodID(activityClass, "setTouchLayoutMode", "(I)V")
		: nullptr;
	if ( setLayoutMethod )
	{
		env->CallVoidMethod(activity, setLayoutMethod, requestedMode);
	}

	const bool failed = !activityClass || !setLayoutMethod || env->ExceptionCheck();
	if ( env->ExceptionCheck() )
	{
		env->ExceptionClear();
	}
	if ( activityClass )
	{
		env->DeleteLocalRef(activityClass);
	}
	env->DeleteLocalRef(activity);

	if ( failed )
	{
		if ( !failureLogged )
		{
			failureLogged = true;
			SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
				"BARONY_ANDROID_TOUCH_LAYOUT_FAILED stage=callback");
		}
		return;
	}

	lastMode = requestedMode;
	failureLogged = false;
	const char* modeName = mode == AndroidTouchLayoutMode::Gameplay
		? "GAMEPLAY"
		: (mode == AndroidTouchLayoutMode::UI ? "UI" : "MENU");
	SDL_Log("BARONY_ANDROID_TOUCH_LAYOUT mode=%s", modeName);
}

#else

void androidUpdateTouchLayoutMode(AndroidTouchLayoutMode)
{
}

#endif
