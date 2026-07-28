#include "android_data_bridge.hpp"

#ifdef __ANDROID__

#include <jni.h>

#include <SDL.h>
#include <SDL_system.h>

void androidOpenStorageManager()
{
	JNIEnv* env = static_cast<JNIEnv*>(SDL_AndroidGetJNIEnv());
	jobject activity = static_cast<jobject>(SDL_AndroidGetActivity());
	if ( !env || !activity )
	{
		SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
			"BARONY_ANDROID_STORAGE_MANAGER_FAILED stage=activity");
		return;
	}

	jclass activityClass = env->GetObjectClass(activity);
	jmethodID showStorageManager = activityClass
		? env->GetMethodID(activityClass, "showStorageManager", "()V")
		: nullptr;
	if ( showStorageManager )
	{
		env->CallVoidMethod(activity, showStorageManager);
	}

	const bool failed = !activityClass
		|| !showStorageManager
		|| env->ExceptionCheck();
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
		SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
			"BARONY_ANDROID_STORAGE_MANAGER_FAILED stage=callback");
		return;
	}
	SDL_Log("BARONY_ANDROID_STORAGE_MANAGER_OPENED");
}

#else

void androidOpenStorageManager()
{
}

#endif
