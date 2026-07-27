/*-------------------------------------------------------------------------------

	BARONY
	File: sound.cpp
	Desc: various sound functions

	Copyright 2013-2016 (c) Turning Wheel LLC, all rights reserved.
	See LICENSE for details.

-------------------------------------------------------------------------------*/

#include "../../main.hpp"
#include "../../files.hpp"
#include "../../game.hpp"
#include "sound.hpp"
#ifndef EDITOR
#include "../../player.hpp"
#endif

#ifdef USE_FMOD
#include "fmod_errors.h"
#elif defined USE_OPENAL
#ifdef USE_TREMOR
#include <tremor/ivorbisfile.h>
#else
#include <ogg/ogg.h>
#include <vorbis/vorbisfile.h>
#include <vorbis/codec.h>
#endif
#endif

#ifdef USE_FMOD
#elif defined USE_OPENAL
void setAudioDevice(const std::string& device)
{
	// OpenAL Soft selects Android's system-managed output device. Runtime
	// switching is not exposed by Barony's legacy OpenAL backend.
	(void)device;
}

void setRecordDevice(const std::string& device)
{
	(void)device;
}
#else
void setGlobalVolume(real_t master, real_t music, real_t gameplay, real_t ambient, real_t environment, real_t notification)
{
	return;
}
void setAudioDevice(const std::string& device) 
{
	return;
}
#endif

#ifdef USE_FMOD

bool FMODErrorCheck()
{
	if (no_sound)
	{
		return false;
	}
	if (fmod_result != FMOD_OK)
	{
		printlog("[FMOD Error] Error Code (%d): \"%s\"\n", fmod_result, FMOD_ErrorString(fmod_result)); //Report the FMOD error.
		return true;
	}

	return false;
}

void setAudioDevice(const std::string& device) {
	int selected_driver = 0;
	int numDrivers = 0;
	fmod_system->getNumDrivers(&numDrivers);
	for (int i = 0; i < numDrivers; ++i) {
		FMOD_GUID guid;
		fmod_result = fmod_system->getDriverInfo(i, nullptr, 0, &guid, nullptr, nullptr, nullptr);

		uint32_t _1; memcpy(&_1, &guid.Data1, sizeof(_1));
		uint64_t _2; memcpy(&_2, &guid.Data4, sizeof(_2));
		char guid_string[25];
		snprintf(guid_string, sizeof(guid_string), FMOD_AUDIO_GUID_FMT, _1, _2);
		if (!selected_driver && device == guid_string) {
			selected_driver = i;
		}
	}
	fmod_system->setDriver(selected_driver);
}

void setRecordDevice(const std::string& device)
{
#ifndef EDITOR
	int selected_driver = 0;
	int numDrivers = 0;
	fmod_system->getRecordNumDrivers(&numDrivers, nullptr);
	for ( int i = 0; i < numDrivers; ++i ) {
		FMOD_GUID guid;
		constexpr int driverNameLen = 64;
		char driverName[driverNameLen] = "";
		fmod_result = fmod_system->getRecordDriverInfo(i, driverName, driverNameLen, &guid, nullptr, nullptr, nullptr, nullptr);
		if ( strstr(driverName, "[loopback]") )
		{
			continue;
		}
		uint32_t _1; memcpy(&_1, &guid.Data1, sizeof(_1));
		uint64_t _2; memcpy(&_2, &guid.Data4, sizeof(_2));
		char guid_string[25];
		snprintf(guid_string, sizeof(guid_string), FMOD_AUDIO_GUID_FMT, _1, _2);
		if ( !selected_driver && device == guid_string ) {
			selected_driver = i;
		}
	}
	VoiceChat.setRecordingDevice(selected_driver);
#endif
}

void setGlobalVolume(real_t master, real_t music, real_t gameplay, real_t ambient, real_t environment, real_t notification) {
    master = std::min(std::max(0.0, master), 1.0);
    music = std::min(std::max(0.0, music / 4.0), 1.0); // music volume cut in half because the music is loud...
    gameplay = std::min(std::max(0.0, gameplay), 1.0);
    ambient = std::min(std::max(0.0, ambient), 1.0);
    environment = std::min(std::max(0.0, environment), 1.0);
	notification = std::min(std::max(0.0, notification), 1.0);

	music_group->setVolume(master * music);
	sound_group->setVolume(master * gameplay);
	soundAmbient_group->setVolume(master * ambient);
	soundEnvironment_group->setVolume(master * environment);
	music_notification_group->setVolume(master * notification);
	soundNotification_group->setVolume(master * notification);
	music_ensemble_global_send_group->setVolume(1.f);

#ifndef EDITOR
	ensembleSounds.ensemble_recv_global_volume = master * (music * 4);
	ensembleSounds.ensemble_recv_player_volume = master * gameplay;
	if ( VoiceChat.outChannelGroup )
	{
		VoiceChat.outChannelGroup->setVolume(master);
	}
#endif
}

#ifndef EDITOR
	static ConsoleVariable<float> cvar_sfx_notification_music_fade("/sfx_notification_music_fade", 0.5f);
	static ConsoleVariable<float> cvar_sfx_ensemble_music_fade("/sfx_ensemble_music_fade", 0.f);
#endif // !EDITOR

void sound_update(int player, int index, int numplayers)
{
#ifdef DEBUG_EVENT_TIMERS
	auto time1 = std::chrono::high_resolution_clock::now();
	auto time2 = std::chrono::high_resolution_clock::now();
	auto accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
	if ( accum > 5 )
	{
		printlog("Large tick time: [10] %f", accum);
	}
	time1 = std::chrono::high_resolution_clock::now();
#endif

	if (no_sound)
	{
		return;
	}
	if (!fmod_system)
	{
		return;
	}

	FMOD_VECTOR position, forward, up;
	bool playing = false;

	auto& camera = cameras[index];

	position.x = (float)(camera.x);
	position.y = (float)(camera.z / (real_t)32.0);
	position.z = (float)(camera.y);

	/*forward.x = -1.0 * cos(camera.ang) * cos(camera.vang);
	forward.y =  1.0 * sin(camera.vang);
	forward.z = -1.0 * sin(camera.ang) * cos(camera.vang);*/
 
    forward.x = (float)((real_t)1.0 * cos(camera.ang));
    forward.y = 0.f;
    forward.z = (float)((real_t)1.0 * sin(camera.ang));

	/*up.x = -1.0 * cos(camera.ang) * sin(camera.vang);
	up.y =  1.0 * cos(camera.vang);
	up.z = -1.0 * sin(camera.ang) * sin(camera.vang);*/
    up.x = 0.f;
    up.y = 1.f;
    up.z = 0.f;

	//FMOD_System_Set3DListenerAttributes(fmod_system, 0, &position, &velocity, &forward, &up);
	fmod_system->set3DNumListeners(numplayers);

#ifdef DEBUG_EVENT_TIMERS
	time2 = std::chrono::high_resolution_clock::now();
	accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
	if ( accum > 5 )
	{
		printlog("Large tick time: [11] %f", accum);
	}
	time1 = std::chrono::high_resolution_clock::now();
#endif

	fmod_system->set3DListenerAttributes(player, &position, nullptr, &forward, &up);

#ifdef DEBUG_EVENT_TIMERS
	time2 = std::chrono::high_resolution_clock::now();
	accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
	if ( accum > 5 )
	{
		printlog("Large tick time: [12] %f", accum);
	}
	time1 = std::chrono::high_resolution_clock::now();
#endif

	if (player == 0) {
#ifndef EDITOR
		//Fade in the currently playing music.
		bool notificationPlaying = false;
		if ( music_notification_group )
		{
			music_notification_group->isPlaying(&notificationPlaying);
		}
		bool ensemblePlaying = false;
		if ( music_ensemble_global_send_group )
		{
			music_ensemble_global_send_group->isPlaying(&ensemblePlaying);
			if ( ensemblePlaying )
			{
				bool ensemblePaused = false;
				music_ensemble_global_send_group->getPaused(&ensemblePaused); // if playing, then check if paused
				if ( ensemblePaused )
				{
					ensemblePlaying = false;
				}
				else
				{
					Uint32 globalEnsemblePlaying = 0;
					Uint32 localEnsemblePlaying = 0;
					for ( int i = 0; i < MAXPLAYERS; ++i )
					{
						if ( players[i]->isLocalPlayerAlive() )
						{
							globalEnsemblePlaying |= (players[i]->mechanics.ensembleDataUpdate >> 16) & 0xFFFF;
							localEnsemblePlaying |= (players[i]->mechanics.ensembleDataUpdate >> 8) & 0xFF;
						}
						/*if ( players[i]->entity && !client_disconnected[i] )
						{
							// if we want other players to override the main soundtrack with local sound
							localEnsemblePlaying |= (players[i]->mechanics.ensembleDataUpdate >> 8) & 0xFF;
						}*/
					}
					if ( globalEnsemblePlaying == 0 || (*cvar_ensemble_vol_bg <= -79.f && localEnsemblePlaying == 0)
						|| (!instrument_bg_enabled && localEnsemblePlaying == 0) )
					{
						ensemblePlaying = false;
					}
				}
			}
		}
#endif

#ifdef DEBUG_EVENT_TIMERS
		time2 = std::chrono::high_resolution_clock::now();
		accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
		if ( accum > 5 )
		{
			printlog("Large tick time: [13] %f", accum);
		}
		time1 = std::chrono::high_resolution_clock::now();
#endif

		if (music_channel)
		{
			playing = false;
			music_channel->isPlaying(&playing);
			if (playing)
			{
				float volume = 1.0f;
				music_channel->getVolume(&volume);

#ifdef DEBUG_EVENT_TIMERS
				time2 = std::chrono::high_resolution_clock::now();
				accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
				if ( accum > 5 )
				{
					printlog("Large tick time: [14] %f", accum);
				}
				time1 = std::chrono::high_resolution_clock::now();
#endif
#ifdef EDITOR
				if ( volume < 1.0f )
				{
					volume += fadein_increment * 2;
					if ( volume > 1.0f )
					{
						volume = 1.0f;
					}
					music_channel->setVolume(volume);
				}
#else
				if ( notificationPlaying && volume > 0.0f )
				{
					volume -= fadeout_increment * 5;
					if ( volume < *cvar_sfx_notification_music_fade )
					{
						volume = *cvar_sfx_notification_music_fade;
					}
					music_channel->setVolume(volume);
				}
				else if ( ensemblePlaying )
				{
					volume -= fadeout_increment * 5;
					if ( volume < *cvar_sfx_ensemble_music_fade )
					{
						volume = *cvar_sfx_ensemble_music_fade;
					}
					music_channel->setVolume(volume);
				}
				else if (volume < 1.0f)
				{
					volume += fadein_increment * 2;
					if (volume > 1.0f)
					{
						volume = 1.0f;
					}
					music_channel->setVolume(volume);
				}
#endif
#ifdef DEBUG_EVENT_TIMERS
				time2 = std::chrono::high_resolution_clock::now();
				accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
				if ( accum > 5 )
				{
					printlog("Large tick time: [15] %f", accum);
				}
				time1 = std::chrono::high_resolution_clock::now();
#endif
			}
		}

		//The following makes crossfading possible. Fade out the last playing music. //TODO: Support for saving music so that it can be resumed (for stuff interrupting like combat music).
		if (music_channel2)
		{
			playing = false;

#ifdef DEBUG_EVENT_TIMERS
			time2 = std::chrono::high_resolution_clock::now();
			accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
			if ( accum > 5 )
			{
				printlog("Large tick time: [16] %f", accum);
			}
			time1 = std::chrono::high_resolution_clock::now();
#endif

			music_channel2->isPlaying(&playing);
			if (playing)
			{
				float volume = 0.0f;
				music_channel2->getVolume(&volume);

#ifdef DEBUG_EVENT_TIMERS
				time2 = std::chrono::high_resolution_clock::now();
				accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
				if ( accum > 5 )
				{
					printlog("Large tick time: [17] %f", accum);
				}
				time1 = std::chrono::high_resolution_clock::now();
#endif

				if (volume > 0.0f)
				{
					volume -= fadeout_increment * 2;
					if (volume < 0.0f)
					{
						volume = 0.0f;
					}
					music_channel2->setVolume(volume);
				}

#ifdef DEBUG_EVENT_TIMERS
				time2 = std::chrono::high_resolution_clock::now();
				accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
				if ( accum > 5 )
				{
					printlog("Large tick time: [18] %f", accum);
				}
				time1 = std::chrono::high_resolution_clock::now();
#endif
			}
		}
	}

#ifdef DEBUG_EVENT_TIMERS
	time2 = std::chrono::high_resolution_clock::now();
	accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
	if ( accum > 5 )
	{
		printlog("Large tick time: [19] %f", accum);
	}
	time1 = std::chrono::high_resolution_clock::now();
#endif

	if (player == numplayers - 1) {
#ifndef EDITOR
		VoiceChat.update();
#endif
		fmod_system->update();
	}

#ifdef DEBUG_EVENT_TIMERS
	time2 = std::chrono::high_resolution_clock::now();
	accum = 1000 * std::chrono::duration_cast<std::chrono::duration<double>>(time2 - time1).count();
	if ( accum > 5 )
	{
		printlog("Large tick time: [20] %f", accum);
	}
	time1 = std::chrono::high_resolution_clock::now();
#endif
}

#elif defined USE_OPENAL

struct OPENAL_BUFFER {
	ALuint id;
	bool stream;
	char oggfile[64];
	int pcm_peak;
};
struct OPENAL_SOUND {
	ALuint id;
	OPENAL_CHANNELGROUP *group;
	float volume;
	OPENAL_BUFFER *buffer;
	bool active;
	char* oggdata;
	size_t oggdata_length;
	size_t ogg_seekoffset;
	OggVorbis_File oggStream;
	vorbis_info* vorbisInfo;
	vorbis_comment* vorbisComment;
	ALuint streambuff[4];
	bool loop;
	bool stream_active;
	bool stream_opened;
	bool pcm_logged_ready;
	bool source_logged_play;
	int indice;
};

struct OPENAL_CHANNELGROUP {
	float volume;
	int num;
	int cap;
	OPENAL_SOUND **sounds;
};

SDL_mutex *openal_mutex;

static size_t openal_oggread(void* ptr, size_t size, size_t nmemb, void* datasource) {
	OPENAL_SOUND* self = (OPENAL_SOUND*)datasource;
	if (!size || !nmemb || self->ogg_seekoffset >= self->oggdata_length)
	{
		return 0;
	}
	const size_t available = self->oggdata_length - self->ogg_seekoffset;
	const size_t items = std::min(nmemb, available / size);
	const size_t bytes = items * size;
	memcpy(ptr, self->oggdata + self->ogg_seekoffset, bytes);
	self->ogg_seekoffset += bytes;
	return items;
}

static int openal_oggseek(void* datasource, ogg_int64_t offset, int whence) {
	OPENAL_SOUND* self = (OPENAL_SOUND*)datasource;
	ogg_int64_t seek_offset = 0;

	switch(whence) {
	case SEEK_CUR:
		seek_offset = self->ogg_seekoffset + offset;
		break;
	case SEEK_END:
		seek_offset = self->oggdata_length + offset;
		break;
	case SEEK_SET:
		seek_offset = offset;
		break;
	default:
		return -1;
	}
	if (seek_offset < 0 || static_cast<uint64_t>(seek_offset) > self->oggdata_length)
	{
		return -1;
	}

	self->ogg_seekoffset = static_cast<size_t>(seek_offset);
	return 0;
}

static int openal_oggclose(void* datasource) {
	return 0;
}

static long int openal_oggtell(void* datasource) {
	OPENAL_SOUND* self = (OPENAL_SOUND*)datasource;
	return static_cast<long int>(self->ogg_seekoffset);
}

static int openal_oggopen(OPENAL_SOUND *self, const char* oggfile) {
	File *f = openDataFile(oggfile, "rb");
	int err;

	ov_callbacks oggcb = {openal_oggread, openal_oggseek, openal_oggclose, openal_oggtell};

	if(!f) {
		return 0;
	}

	self->ogg_seekoffset = 0;
	self->oggdata_length = f->size();

	self->oggdata = (char*)malloc(self->oggdata_length);
	if (!self->oggdata
		|| f->read(self->oggdata, sizeof(char), self->oggdata_length) != self->oggdata_length)
	{
		printlog("[OpenAL]: unable to read music stream %s", oggfile);
		free(self->oggdata);
		self->oggdata = nullptr;
		FileIO::close(f);
		return 0;
	}
	FileIO::close(f);

	const int openResult = ov_open_callbacks(self, &self->oggStream, 0, 0, oggcb);
	if(openResult) {
		printlog("[OpenAL]: unable to open Vorbis music stream %s (error %d)", oggfile, openResult);
		free(self->oggdata);
		self->oggdata = nullptr;
		return 0;
	}

	self->vorbisInfo = ov_info(&self->oggStream, -1);
	self->vorbisComment = ov_comment(&self->oggStream, -1);
	if (!self->vorbisInfo)
	{
		printlog("[OpenAL]: invalid Vorbis stream info for %s", oggfile);
		ov_clear(&self->oggStream);
		free(self->oggdata);
		self->oggdata = nullptr;
		return 0;
	}

	alGenBuffers(4, self->streambuff);
	#ifdef ANDROID
	printlog("BARONY_ANDROID_AUDIO_STREAM_OPEN file=%s rate=%ld channels=%d",
		oggfile, self->vorbisInfo->rate, self->vorbisInfo->channels);
	#endif
	return 1;
}

static int openal_oggrelease(OPENAL_SOUND *self) {
	if (!self->stream_opened)
	{
		return 1;
	}
	alSourceStop(self->id);
	ov_raw_seek(&self->oggStream, 0);
	int queued;
	alGetSourcei(self->id, AL_BUFFERS_QUEUED, &queued);
	while(queued--) {
		ALuint buffer;
		alSourceUnqueueBuffers(self->id, 1, &buffer);
	}
	alDeleteBuffers(4, self->streambuff);
	ov_clear(&self->oggStream);
	free(self->oggdata);
	self->oggdata = nullptr;
	self->stream_opened = false;
	return 1;
}

static int openal_streamread(OPENAL_SOUND *self, ALuint buffer) {
	#define OGGSIZE 65536
	char pcm[OGGSIZE];
	int size = 0;
	int section;
	int result;
	int recoverableHoles = 0;
	bool rewound = false;

	while (size < OGGSIZE) {
		#ifdef USE_TREMOR
		result = ov_read(&self->oggStream, pcm+size, OGGSIZE -size, &section);
		#else
		result = ov_read(&self->oggStream, pcm+size, OGGSIZE -size, 0, 2, 1, &section);
		#endif
		if(result>0)
		{
			size += result;
			recoverableHoles = 0;
		}
		else if (result == OV_HOLE && recoverableHoles++ < 8)
		{
			continue;
		}
		else if (result == 0 && self->loop && !rewound
			&& ov_raw_seek(&self->oggStream, 0) == 0)
		{
			rewound = true;
			continue;
		}
		else
		{
			if (result < 0)
			{
				printlog("[OpenAL]: Vorbis stream decode error %d in %s",
					result, self->buffer->oggfile);
			}
			break;
		}
	}

	if(size==0) {
		return 0;
	}
	#ifdef ANDROID
	if (!self->pcm_logged_ready)
	{
		const int16_t* samples = reinterpret_cast<const int16_t*>(pcm);
		const int sampleCount = size / static_cast<int>(sizeof(int16_t));
		for (int i = 0; i < sampleCount; ++i)
		{
			if (samples[i] != 0)
			{
				printlog("BARONY_ANDROID_AUDIO_PCM_READY file=%s bytes=%d rate=%ld channels=%d",
					self->buffer->oggfile, size, self->vorbisInfo->rate, self->vorbisInfo->channels);
				self->pcm_logged_ready = true;
				break;
			}
		}
	}
	#endif
	alBufferData(buffer, 
		(self->vorbisInfo->channels==1)?AL_FORMAT_MONO16:AL_FORMAT_STEREO16, 
		pcm, size, self->vorbisInfo->rate);

	return 1;

	#undef OGGSIZE
}

static int openal_streamupdate(OPENAL_SOUND* self) {
	int processed;
	int active = 1;

	alGetSourcei(self->id, AL_BUFFERS_PROCESSED, &processed);

	while(processed--) {
		ALuint buffer;

		alSourceUnqueueBuffers(self->id, 1, &buffer);

		active = openal_streamread(self, buffer);
		if(active)
			alSourceQueueBuffers(self->id, 1, &buffer);
	}
	if (active)
	{
		ALint state = AL_INITIAL;
		ALint queued = 0;
		alGetSourcei(self->id, AL_SOURCE_STATE, &state);
		alGetSourcei(self->id, AL_BUFFERS_QUEUED, &queued);
		if (state == AL_STOPPED && queued > 0)
		{
			alSourcePlay(self->id);
			#ifdef ANDROID
			printlog("BARONY_ANDROID_AUDIO_STREAM_RECOVERED file=%s queued=%d",
				self->buffer->oggfile, queued);
			#endif
		}
	}
	self->stream_active = active;

	return active;
}

bool sfxUseDynamicAmbientVolume = true;
bool sfxUseDynamicEnvironmentVolume = true;

ALCcontext *openal_context = nullptr;
ALCdevice  *openal_device = nullptr;

//#define openal_maxchannels 100

OPENAL_BUFFER** sounds = nullptr;
OPENAL_BUFFER** minesmusic = NULL;
OPENAL_BUFFER** swampmusic = NULL;
OPENAL_BUFFER** labyrinthmusic = NULL;
OPENAL_BUFFER** ruinsmusic = NULL;
OPENAL_BUFFER** underworldmusic = NULL;
OPENAL_BUFFER** hellmusic = NULL;
OPENAL_BUFFER** intromusic = NULL;
OPENAL_BUFFER* intermissionmusic = NULL;
OPENAL_BUFFER* minetownmusic = NULL;
OPENAL_BUFFER* splashmusic = NULL;
OPENAL_BUFFER* librarymusic = NULL;
OPENAL_BUFFER* shopmusic = NULL;
OPENAL_BUFFER* storymusic = NULL;
OPENAL_BUFFER** minotaurmusic = NULL;
OPENAL_BUFFER* herxmusic = NULL;
OPENAL_BUFFER* templemusic = NULL;
OPENAL_BUFFER* endgamemusic = NULL;
OPENAL_BUFFER* devilmusic = NULL;
OPENAL_BUFFER* escapemusic = NULL;
OPENAL_BUFFER* sanctummusic = NULL;
OPENAL_BUFFER* introductionmusic = NULL;
OPENAL_BUFFER** cavesmusic = NULL;
OPENAL_BUFFER** citadelmusic = NULL;
OPENAL_BUFFER* gnomishminesmusic = NULL;
OPENAL_BUFFER* greatcastlemusic = NULL;
OPENAL_BUFFER* sokobanmusic = NULL;
OPENAL_BUFFER* caveslairmusic = NULL;
OPENAL_BUFFER* bramscastlemusic = NULL;
OPENAL_BUFFER* hamletmusic = NULL;
OPENAL_BUFFER* tutorialmusic = nullptr;
OPENAL_BUFFER* gameovermusic = nullptr;
OPENAL_BUFFER* introstorymusic = nullptr;
bool levelmusicplaying = false;

OPENAL_SOUND* music_channel = nullptr;
OPENAL_SOUND* music_channel2 = nullptr;
OPENAL_SOUND* music_resume = nullptr;

OPENAL_CHANNELGROUP *sound_group = NULL;
OPENAL_CHANNELGROUP *soundAmbient_group = NULL;
OPENAL_CHANNELGROUP *soundEnvironment_group = NULL;
OPENAL_CHANNELGROUP *music_group = NULL;
OPENAL_CHANNELGROUP *music_notification_group = NULL;

float fadein_increment = 0.002f;
float default_fadein_increment = 0.002f;
float fadeout_increment = 0.005f;
float default_fadeout_increment = 0.005f;

#define MAXSOUND 1024
OPENAL_SOUND openal_sounds[MAXSOUND];
int lower_freechannel = 0;
int upper_unfreechannel = 0;

SDL_Thread* openal_soundthread;
bool OpenALSoundON = false;
static bool openal_initialized = false;
#ifdef ANDROID
static bool openal_sfx_logged_ready = false;
#endif

void OPENAL_RemoveChannelGroup(OPENAL_SOUND *channel, OPENAL_CHANNELGROUP *group);

static void private_OPENAL_Channel_Stop(OPENAL_SOUND* channel) {
	// stop and delete Sound (channel)
	channel->stream_active = false;
	alSourceStop(channel->id);
	if(channel->group)
		OPENAL_RemoveChannelGroup(channel, channel->group);
	if(channel->buffer->stream && channel->stream_opened)
		openal_oggrelease(channel);
	alDeleteSources( 1, &channel->id );
	//free(channel);
	channel->active = false;
}


int OPENAL_ThreadFunction(void* data) {
	(void)data;
	#ifdef ANDROID
	Uint32 last_channel_log_ticks = 0;
	#endif
	while(OpenALSoundON) {
		SDL_LockMutex(openal_mutex);

		// Updates Stream channel
		for (int i=0; i<upper_unfreechannel; i++) {
			if(openal_sounds[i].active && openal_sounds[i].buffer->stream && openal_sounds[i].stream_active) {
				openal_streamupdate(&openal_sounds[i]);
			}
		}

		// check finished sound to free them, unless it's a streamed channel...
		for (int i=0; i<upper_unfreechannel; i++) {
			if(openal_sounds[i].active && !openal_sounds[i].buffer->stream) {
				ALint state = 0;
				alGetSourcei(openal_sounds[i].id, AL_SOURCE_STATE, &state);
				if(!(state==AL_PLAYING || state==AL_PAUSED || state==AL_INITIAL)) {
					private_OPENAL_Channel_Stop(&openal_sounds[i]);
					if (lower_freechannel > i)
						lower_freechannel = i;
				}
			}
		}
		while ((upper_unfreechannel > 0) && (!openal_sounds[upper_unfreechannel-1].active))
			--upper_unfreechannel;

		#ifdef ANDROID
		const Uint32 now = SDL_GetTicks();
		if (now - last_channel_log_ticks >= 5000)
		{
			int active = 0;
			int playing = 0;
			int paused = 0;
			int initial = 0;
			int stopped = 0;
			int streaming = 0;
			int looping = 0;
			int gameplay = 0;
			int ambient = 0;
			int environment = 0;
			int music = 0;
			int notification = 0;
			int ungrouped = 0;
			for (int i = 0; i < upper_unfreechannel; ++i)
			{
				if (!openal_sounds[i].active)
				{
					continue;
				}
				++active;
				streaming += openal_sounds[i].buffer->stream ? 1 : 0;
				looping += openal_sounds[i].loop ? 1 : 0;
				if (openal_sounds[i].group == sound_group) { ++gameplay; }
				else if (openal_sounds[i].group == soundAmbient_group) { ++ambient; }
				else if (openal_sounds[i].group == soundEnvironment_group) { ++environment; }
				else if (openal_sounds[i].group == music_group) { ++music; }
				else if (openal_sounds[i].group == music_notification_group) { ++notification; }
				else { ++ungrouped; }
				ALint state = 0;
				alGetSourcei(openal_sounds[i].id, AL_SOURCE_STATE, &state);
				switch (state)
				{
					case AL_PLAYING: ++playing; break;
					case AL_PAUSED: ++paused; break;
					case AL_INITIAL: ++initial; break;
					case AL_STOPPED: ++stopped; break;
					default: break;
				}
			}
			printlog("BARONY_ANDROID_AUDIO_CHANNELS active=%d playing=%d paused=%d initial=%d stopped=%d streaming=%d looping=%d gameplay=%d ambient=%d environment=%d music=%d notification=%d ungrouped=%d upper=%d",
				active, playing, paused, initial, stopped, streaming, looping, gameplay,
				ambient, environment, music, notification, ungrouped, upper_unfreechannel);
			last_channel_log_ticks = now;
		}
		#endif

		SDL_UnlockMutex(openal_mutex);
		
		SDL_Delay(100);
	}
	return 1;
}

int initOPENAL()
{
	if(openal_initialized)
		return 1;
	#ifdef ANDROID
	openal_sfx_logged_ready = false;
	#endif

	openal_device = alcOpenDevice(NULL); // preferred device
	if(!openal_device)
		return 0;

	openal_context = alcCreateContext(openal_device,NULL);
	if(!openal_context)
	{
		alcCloseDevice(openal_device);
		openal_device = nullptr;
		return 0;
	}

	if (!alcMakeContextCurrent(openal_context))
	{
		alcDestroyContext(openal_context);
		openal_context = nullptr;
		alcCloseDevice(openal_device);
		openal_device = nullptr;
		return 0;
	}

	alDistanceModel(AL_INVERSE_DISTANCE_CLAMPED);
	alDopplerFactor(2.0f);

	// creates channels groups
	sound_group = (OPENAL_CHANNELGROUP*)malloc(sizeof(OPENAL_CHANNELGROUP));
	soundAmbient_group = (OPENAL_CHANNELGROUP*)malloc(sizeof(OPENAL_CHANNELGROUP));
	soundEnvironment_group = (OPENAL_CHANNELGROUP*)malloc(sizeof(OPENAL_CHANNELGROUP));
	music_group = (OPENAL_CHANNELGROUP*)malloc(sizeof(OPENAL_CHANNELGROUP));
	music_notification_group = (OPENAL_CHANNELGROUP*)malloc(sizeof(OPENAL_CHANNELGROUP));
	memset(sound_group, 0, sizeof(OPENAL_CHANNELGROUP));
	memset(soundAmbient_group, 0, sizeof(OPENAL_CHANNELGROUP));
	memset(soundEnvironment_group, 0, sizeof(OPENAL_CHANNELGROUP));
	memset(music_group, 0, sizeof(OPENAL_CHANNELGROUP));
	memset(music_notification_group, 0, sizeof(OPENAL_CHANNELGROUP));
	sound_group->volume = 1.0f;
	soundAmbient_group->volume = 1.0f;
	soundEnvironment_group->volume = 1.0f;
	music_group->volume = 1.0f;
	music_notification_group->volume = 1.0f;

	memset(openal_sounds, 0, sizeof(openal_sounds));
	lower_freechannel = 0;
	upper_unfreechannel = 0;

	OpenALSoundON = true;
	openal_mutex = SDL_CreateMutex();
	openal_soundthread = SDL_CreateThread(OPENAL_ThreadFunction, "openal", NULL);

	openal_initialized = true;

#ifdef NINTENDO
	//TODO: Do we also want this on other platforms?
	// print source limit
	ALCint size = -1;
	alcGetIntegerv(openal_device, ALC_MONO_SOURCES, 1, &size);
	printlog("openAL: max mono sources: %d", size);
	size = -1;
	alcGetIntegerv(openal_device, ALC_STEREO_SOURCES, 1, &size);
	printlog("openAL: max stereo sources: %d", size);
#endif // NINTENDO

	return 1;
}

int closeOPENAL()
{
	if(!OpenALSoundON) return 0;

	OpenALSoundON = false;
	int i = 0;
	SDL_WaitThread(openal_soundthread, &i);
	if(i!=1) {
		printlog("Warning, unable to stop Openal thread\n");
	}

	if(openal_mutex) {
		SDL_DestroyMutex(openal_mutex);
		openal_mutex = NULL;
	}

	// Stop every source before deleting its buffers or destroying the context.
	for (int i=0; i<upper_unfreechannel; i++) {
		if(openal_sounds[i].active) {
			private_OPENAL_Channel_Stop(&openal_sounds[i]);
		}
	}
	freeSoundResources();

	alcMakeContextCurrent(NULL);
	alcDestroyContext(openal_context);
	openal_context = NULL;
	alcCloseDevice(openal_device);
	openal_device = NULL;
	openal_initialized = false;

	return 1;
}


static int get_firstfreechannel()
{
	int i = lower_freechannel;
	while ((i<MAXSOUND) && (openal_sounds[i].active))
		i++;
	if (i<MAXSOUND) {
		return i;
	}
	//no free channels, force free last one :(
	i = MAXSOUND-1;
	// TODO, check if it's a Stream one, then skip it if yes
	while((i>0) && (openal_sounds[i].buffer->stream))
		--i;

	private_OPENAL_Channel_Stop(&openal_sounds[i]);

	return i;
}

void setGlobalVolume(real_t master, real_t music, real_t gameplay, real_t ambient, real_t environment, real_t notification) {
    master = std::min(std::max(0.0, master), 1.0);
    music = std::min(std::max(0.0, music / 4.0), 1.0); // music volume cut in half because the music is loud...
    gameplay = std::min(std::max(0.0, gameplay), 1.0);
    ambient = std::min(std::max(0.0, ambient), 1.0);
    environment = std::min(std::max(0.0, environment), 1.0);
	notification = std::min(std::max(0.0, notification), 1.0);

	OPENAL_ChannelGroup_SetVolume(music_group, master * music);
	OPENAL_ChannelGroup_SetVolume(sound_group, master * gameplay);
	OPENAL_ChannelGroup_SetVolume(soundAmbient_group, master * ambient);
	OPENAL_ChannelGroup_SetVolume(soundEnvironment_group, master * environment);
	OPENAL_ChannelGroup_SetVolume(music_notification_group, master * notification);
}

void sound_update(int player, int index, int numplayers)
{
	if (no_sound)
	{
		return;
	}
	if (!openal_device)
	{
		return;
	}

	FMOD_VECTOR position;

	auto& camera = cameras[index];
	if ( splitscreen )
	{
		camera = cameras[0];
	}

	position.x = -camera.y;
	position.y = -camera.z / 32;
	position.z = -camera.x;

	/*double cosroll = cos(0);
	double cosyaw = cos(camera.ang);
	double cospitch = cos(camera.vang);
	double sinroll = sin(0);
	double sinyaw = sin(camera.ang);
	double sinpitch = sin(camera.vang);

	double rx = sinroll*sinyaw - cosroll*sinpitch*cosyaw;
	double ry = sinroll*cosyaw + cosroll*sinpitch*sinyaw;
	double rz = cosroll*cospitch;*/

	float vector[6];
	vector[0] = 1 * sin(camera.ang);
	vector[1] = 0;
	vector[2] = 1 * cos(camera.ang);
	/*forward.x = rx;
	forward.y = ry;
	forward.z = rz;*/

	/*rx = sinroll*sinyaw - cosroll*cospitch*cosyaw;
	ry = sinroll*cosyaw + cosroll*cospitch*sinyaw;
	rz = cosroll*sinpitch;*/

	vector[3] = 0;
	vector[4] = 1;
	vector[5] = 0;
	/*up.x = rx;
	up.y = ry;
	up.z = rz;*/

	alListenerfv(AL_POSITION, (float*)&position);
	alListenerfv(AL_ORIENTATION, vector);
	//FMOD_System_Set3DListenerAttributes(fmod_system, 0, &position, 0, &forward, &up);

	//Fade in the currently playing music.
	if (player == 0) {
		if (music_channel)
		{
			ALint playing = 0;
			alGetSourcei( music_channel->id, AL_SOURCE_STATE, &playing );
			if (playing==AL_PLAYING)
			{
				float volume = music_channel->volume;

				if (volume < 1.0f)
				{
					volume += fadein_increment * 2;
					if (volume > 1.0f)
					{
						volume = 1.0f;
					}
					OPENAL_Channel_SetVolume(music_channel, volume);
				}
			}
		}
		//The following makes crossfading possible. Fade out the last playing music. //TODO: Support for saving music so that it can be resumed (for stuff interrupting like combat music).
		if (music_channel2)
		{
			ALint playing = 0;
			alGetSourcei( music_channel2->id, AL_SOURCE_STATE, &playing );
			if (playing)
			{
				float volume = music_channel2->volume;

				if (volume > 0.0f)
				{
					//volume -= 0.001f;
					//volume -= 0.005f;
					volume -= fadeout_increment * 2;
					if (volume < 0.0f)
					{
						volume = 0.0f;
					}
					OPENAL_Channel_SetVolume(music_channel2, volume);
				} else {
					/*OPENAL_Channel_Stop(music_channel2);
					music_channel2 = NULL;*/
					OPENAL_Channel_Pause(music_channel2);
				}
			}
		}
	}
}

void OPENAL_Channel_SetVolume(OPENAL_SOUND *channel, float f) {
	channel->volume = f;
	if(channel->group)
		f *= channel->group->volume;
	alSourcef(channel->id, AL_GAIN, f);
}

void OPENAL_ChannelGroup_Stop(OPENAL_CHANNELGROUP* group) {
	for (int i = 0; i< group->num; i++) {
		if (group->sounds[i])
			alSourceStop( group->sounds[i]->id );
	}
}

void OPENAL_ChannelGroup_SetVolume(OPENAL_CHANNELGROUP* group, float f) {
	group->volume = f;
	for (int i = 0; i< group->num; i++) {
		if (group->sounds[i])
			alSourcef( group->sounds[i]->id, AL_GAIN, f*group->sounds[i]->volume );
	}
}

void OPENAL_Channel_SetChannelGroup(OPENAL_SOUND *channel, OPENAL_CHANNELGROUP *group) {
	if (!channel || !group || channel->group == group)
	{
		return;
	}
	if (channel->group)
	{
		OPENAL_RemoveChannelGroup(channel, channel->group);
	}
	if(group->num==group->cap) {
		group->cap += 8;
		group->sounds = (OPENAL_SOUND**)realloc(group->sounds, group->cap*sizeof(OPENAL_SOUND*));
	}
	alSourcef(channel->id, AL_GAIN, channel->volume * group->volume);
	group->sounds[group->num++] = channel;
	channel->group = group;
}

void OPENAL_RemoveChannelGroup(OPENAL_SOUND *channel, OPENAL_CHANNELGROUP *group) {
	int i = 0;
	while ((i<group->num) && (channel!=group->sounds[i]))
		i++;
	if(i==group->num)
		return;
	memmove(group->sounds+i, group->sounds+i+1, sizeof(OPENAL_SOUND*)*(group->num-(i+1)));
	group->num--;
}

static size_t openal_file_oggread(void* ptr, size_t size, size_t nmemb, void* datasource) {
	File* file = (File*)datasource;
	return file->read(ptr, size, nmemb);
}

static int openal_file_oggseek(void* datasource, ogg_int64_t offset, int whence) {
	File* file = (File*)datasource;
	int result = -1;
	switch (whence) {
	case SEEK_CUR:
		result = file->seek((ptrdiff_t)offset, File::SeekMode::ADD);
		break;
	case SEEK_END:
		result = file->seek((ptrdiff_t)offset, File::SeekMode::SETEND);
		break;
	case SEEK_SET:
		result = file->seek((ptrdiff_t)offset, File::SeekMode::SET);
		break;
	default:
		return -1;
	}
	// FilePC reports EOF as a failed seek, although Vorbis treats seeking to
	// exactly one byte past the last sample as a valid operation.
	if (result != 0 && file->tell() == static_cast<long int>(file->size()))
	{
		return 0;
	}
	return result;
}

static int openal_file_oggclose(void* datasource) {
	return 0;
}

static long int openal_file_oggtell(void* datasource) {
	File* file = (File*)datasource;
	return file->tell();
}

int OPENAL_CreateSound(const char* name, bool b3D, OPENAL_BUFFER **buffer) {
	*buffer = nullptr;
	File *f = openDataFile(name, "rb");
	if(!f) {
		printlog("Error loading sound %s\n", name);
		return 0;
	}

	ov_callbacks oggcb = { openal_file_oggread, openal_file_oggseek, openal_file_oggclose, openal_file_oggtell };

	OggVorbis_File oggFile{};
	const int openResult = ov_open_callbacks(f, &oggFile, NULL, 0, oggcb);
	if (openResult != 0)
	{
		printlog("[OpenAL]: unable to open sound %s as Vorbis (error %d)", name, openResult);
		FileIO::close(f);
		return 0;
	}

	vorbis_info* pInfo = ov_info(&oggFile, -1);
	if (!pInfo || (pInfo->channels != 1 && pInfo->channels != 2) || pInfo->rate <= 0)
	{
		printlog("[OpenAL]: unsupported Vorbis format for sound %s", name);
		ov_clear(&oggFile);
		FileIO::close(f);
		return 0;
	}

	int channels = pInfo->channels;
	const int freq = pInfo->rate;
	std::vector<char> decodedPcm;
	decodedPcm.reserve(static_cast<size_t>(std::max<ogg_int64_t>(0, ov_pcm_total(&oggFile, -1)))
		* channels * sizeof(int16_t));
	std::array<char, 65536> decodeChunk{};
	int recoverableHoles = 0;
	while (true)
	{
		int bitStream;
		#ifdef USE_TREMOR
		const long bytes = ov_read(&oggFile, decodeChunk.data(), decodeChunk.size(), &bitStream);
		#else
		const long bytes = ov_read(&oggFile, decodeChunk.data(), decodeChunk.size(), 0, 2, 1, &bitStream);
		#endif
		if (bytes > 0)
		{
			decodedPcm.insert(decodedPcm.end(), decodeChunk.data(), decodeChunk.data() + bytes);
			recoverableHoles = 0;
			continue;
		}
		if (bytes == 0)
		{
			break;
		}
		if (bytes == OV_HOLE && recoverableHoles++ < 8)
		{
			continue;
		}
		printlog("[OpenAL]: Vorbis decode error %ld in sound %s", bytes, name);
		ov_clear(&oggFile);
		FileIO::close(f);
		return 0;
	}
	ov_clear(&oggFile);
	FileIO::close(f);
	if (decodedPcm.empty())
	{
		printlog("[OpenAL]: decoded no PCM data for sound %s", name);
		return 0;
	}

	const char* pcmData = decodedPcm.data();
	size_t pcmBytes = decodedPcm.size();
	std::vector<int16_t> monoPcm;
	if(b3D && channels==2) {
		// downmixing sound to mono, because 3D sounds NEEDS mono sound
		const int16_t* stereoPcm = reinterpret_cast<const int16_t*>(decodedPcm.data());
		const size_t frameCount = decodedPcm.size() / (sizeof(int16_t) * 2);
		monoPcm.resize(frameCount);
		for(size_t i = 0; i < frameCount; ++i) {
			monoPcm[i] = static_cast<int16_t>((static_cast<int>(stereoPcm[i * 2])
				+ static_cast<int>(stereoPcm[i * 2 + 1])) / 2);
		}
		pcmData = reinterpret_cast<const char*>(monoPcm.data());
		pcmBytes = monoPcm.size() * sizeof(int16_t);
		channels = 1;
	}

	OPENAL_BUFFER* newBuffer = (OPENAL_BUFFER*)malloc(sizeof(OPENAL_BUFFER));
	if (!newBuffer)
	{
		return 0;
	}
	snprintf(newBuffer->oggfile, sizeof(newBuffer->oggfile), "%s", name);
	newBuffer->stream = false;
	newBuffer->pcm_peak = 0;
	const int16_t* samples = reinterpret_cast<const int16_t*>(pcmData);
	const size_t sampleCount = pcmBytes / sizeof(int16_t);
	for (size_t i = 0; i < sampleCount; ++i)
	{
		const int sample = static_cast<int>(samples[i]);
		const int magnitude = sample < 0 ? -sample : sample;
		newBuffer->pcm_peak = std::max(newBuffer->pcm_peak, magnitude);
	}

	while (alGetError() != AL_NO_ERROR) {}
	alGenBuffers(1, &newBuffer->id);
	if (alGetError() != AL_NO_ERROR)
	{
		printlog("[OpenAL]: unable to allocate PCM buffer for sound %s", name);
		free(newBuffer);
		return 0;
	}
	alBufferData(newBuffer->id, (channels==1)?AL_FORMAT_MONO16:AL_FORMAT_STEREO16,
		pcmData, static_cast<ALsizei>(pcmBytes), freq);
	if (alGetError() != AL_NO_ERROR)
	{
		printlog("[OpenAL]: unable to create PCM buffer for sound %s", name);
		alDeleteBuffers(1, &newBuffer->id);
		free(newBuffer);
		return 0;
	}
	*buffer = newBuffer;
	return 1;
}

bool OPENAL_ChannelGroup_IsPlayingNear(OPENAL_CHANNELGROUP* group, float volume,
	float x, float y, float z, float maxDistanceSquared)
{
	if (!group)
	{
		return false;
	}

	bool found = false;
	SDL_LockMutex(openal_mutex);
	for (int i = 0; i < group->num; ++i)
	{
		OPENAL_SOUND* channel = group->sounds[i];
		if (!channel || !channel->active || fabsf(channel->volume - volume) >= 0.05f)
		{
			continue;
		}

		ALint state = 0;
		alGetSourcei(channel->id, AL_SOURCE_STATE, &state);
		if (state != AL_PLAYING && state != AL_PAUSED)
		{
			continue;
		}

		ALfloat sourceX = 0.f;
		ALfloat sourceY = 0.f;
		ALfloat sourceZ = 0.f;
		alGetSource3f(channel->id, AL_POSITION, &sourceX, &sourceY, &sourceZ);
		const float dx = sourceX - x;
		const float dy = sourceY - y;
		const float dz = sourceZ - z;
		if (dx * dx + dy * dy + dz * dz <= maxDistanceSquared)
		{
			found = true;
			break;
		}
	}
	SDL_UnlockMutex(openal_mutex);
	return found;
}

bool OPENAL_Listener_IsNear(float x, float y, float z, float maxDistanceSquared)
{
	ALfloat listenerX = 0.f;
	ALfloat listenerY = 0.f;
	ALfloat listenerZ = 0.f;
	SDL_LockMutex(openal_mutex);
	alGetListener3f(AL_POSITION, &listenerX, &listenerY, &listenerZ);
	SDL_UnlockMutex(openal_mutex);
	const float dx = listenerX - x;
	const float dy = listenerY - y;
	const float dz = listenerZ - z;
	return dx * dx + dy * dy + dz * dz <= maxDistanceSquared;
}

int OPENAL_CreateStreamSound(const char* name, OPENAL_BUFFER **buffer) {
	*buffer = (OPENAL_BUFFER*)malloc(sizeof(OPENAL_BUFFER));
	(*buffer)->stream = true;
	snprintf((*buffer)->oggfile, sizeof((*buffer)->oggfile), "%s", name);
	(*buffer)->pcm_peak = 0;
	return 1;
}

OPENAL_SOUND* OPENAL_CreateChannel(OPENAL_BUFFER* buffer) {
	//OPENAL_SOUND *channel=(OPENAL_SOUND*)malloc(sizeof(OPENAL_SOUND));

	SDL_LockMutex(openal_mutex);

	int i = get_firstfreechannel();

	if(upper_unfreechannel < (i+1))
		upper_unfreechannel = i+1;
	lower_freechannel = i+1;

	OPENAL_SOUND *channel = &openal_sounds[i];
	alGenSources(1,&channel->id);
	channel->volume = 1.0f;
	channel->group = NULL;
	channel->active = true;
	channel->loop = false;
	channel->buffer = buffer;
	channel->stream_active = false;
	channel->stream_opened = false;
	channel->pcm_logged_ready = false;
	channel->source_logged_play = false;
	channel->indice = i;

	if(buffer->stream) {
		channel->stream_opened = openal_oggopen(channel, buffer->oggfile) != 0;
	} else
		alSourcei(channel->id, AL_BUFFER, buffer->id);
	// default to 2D...
	alSourcei(channel->id,AL_SOURCE_RELATIVE, AL_TRUE);
	alSource3f(channel->id, AL_POSITION, 0, 0, 0);

	SDL_UnlockMutex(openal_mutex);
	return channel;
}

void OPENAL_Channel_IsPlaying(void* channel, ALboolean *playing) {
	ALint state;
	alGetSourcei( ((OPENAL_SOUND*)channel)->id, AL_SOURCE_STATE, &state );
	(*playing) = (state == AL_PLAYING);
}

void OPENAL_Channel_Stop(void* chan) {
	SDL_LockMutex(openal_mutex);

	OPENAL_SOUND* channel = (OPENAL_SOUND*)chan;
	if(channel==NULL || !channel->active) {
		SDL_UnlockMutex(openal_mutex);
		return;
	}

	int i = channel->indice;
	private_OPENAL_Channel_Stop(channel);
	if (lower_freechannel > i)
		lower_freechannel = i;


	SDL_UnlockMutex(openal_mutex);
}

void OPENAL_Channel_Set3DAttributes(OPENAL_SOUND* channel, float x, float y, float z) {

	alSourcei(channel->id,AL_SOURCE_RELATIVE, AL_FALSE);
	alSource3f(channel->id, AL_POSITION, x, y, z);
	alSourcef(channel->id, AL_REFERENCE_DISTANCE, 1.f);	// hardcoding FMOD_System_Set3DSettings(fmod_system, 1.0, 2.0, 1.0);
	alSourcef(channel->id, AL_MAX_DISTANCE, 10.f);		// but this are simply OpenAL default (the 2.0f is used for Dopler only)
}

void OPENAL_Channel_Play(OPENAL_SOUND* channel) {
	SDL_LockMutex(openal_mutex);
	if (channel->buffer->stream && !channel->stream_opened)
	{
		printlog("[OpenAL]: refusing to play unopened stream %s", channel->buffer->oggfile);
		SDL_UnlockMutex(openal_mutex);
		return;
	}

	ALint state;
	alGetSourcei( channel->id, AL_SOURCE_STATE, &state );
	if(state != AL_PLAYING && state != AL_PAUSED) {
		if(channel->buffer->stream) {
			int processed;
			int num_buffers = 4;
			int i;
			ALuint trash[256];

			alGetSourcei(channel->id, AL_BUFFERS_PROCESSED, &processed);
			alSourceUnqueueBuffers(channel->id, processed, trash);

			for(i=0; i<4; i++) {
				if(!openal_streamread(channel, channel->streambuff[i])) {
					num_buffers = i;
					break;
				}
			}

			alSourceQueueBuffers(channel->id, num_buffers, channel->streambuff);
			channel->stream_active = true;
		}
	}
	alSourcePlay(channel->id);
	#ifdef ANDROID
	if (!channel->buffer->stream && !openal_sfx_logged_ready)
	{
		ALint bufferSize = 0;
		ALint frequency = 0;
		ALint channels = 0;
		ALint sourceState = 0;
		alGetBufferi(channel->buffer->id, AL_SIZE, &bufferSize);
		alGetBufferi(channel->buffer->id, AL_FREQUENCY, &frequency);
		alGetBufferi(channel->buffer->id, AL_CHANNELS, &channels);
		alGetSourcei(channel->id, AL_SOURCE_STATE, &sourceState);
		printlog("BARONY_ANDROID_AUDIO_SFX_PLAY file=%s bytes=%d rate=%d channels=%d peak=%d state=%d",
			channel->buffer->oggfile, bufferSize, frequency, channels,
			channel->buffer->pcm_peak, sourceState);
		openal_sfx_logged_ready = true;
	}
	if (channel->buffer->stream && !channel->source_logged_play)
	{
		ALint queued = 0;
		ALint sourceState = 0;
		alGetSourcei(channel->id, AL_BUFFERS_QUEUED, &queued);
		alGetSourcei(channel->id, AL_SOURCE_STATE, &sourceState);
		printlog("BARONY_ANDROID_AUDIO_SOURCE_PLAY file=%s queued=%d state=%d",
			channel->buffer->oggfile, queued, sourceState);
		channel->source_logged_play = true;
	}
	#endif

	SDL_UnlockMutex(openal_mutex);
}

void OPENAL_Channel_Pause(OPENAL_SOUND* channel) {
	alSourcePause(channel->id);
}

void OPENAL_GetBuffer(OPENAL_SOUND* channel, OPENAL_BUFFER** buffer) {
	(*buffer) = channel->buffer;
}

void OPENAL_SetLoop(OPENAL_SOUND* channel, ALboolean looping) {
	channel->loop = looping;
	if(!channel->buffer->stream)
		alSourcei(channel->id, AL_LOOPING, looping);
}

void OPENAL_Channel_GetPosition(OPENAL_SOUND* channel, unsigned int *position) {
	alGetSourcei(channel->id, AL_BYTE_OFFSET, (GLint*)position);
}

void OPENAL_Sound_GetLength(OPENAL_BUFFER* buffer, unsigned int *length) {
	if(!buffer) return;
	alGetBufferi(buffer->id, AL_SIZE, (GLint*)length);
}

void OPENAL_Sound_Release(OPENAL_BUFFER* buffer) {
	if(!buffer) return;
	if(!buffer->stream)
		alDeleteBuffers( 1, &buffer->id );
	free(buffer);
}

void freeOpenALMusic()
{
	OPENAL_Channel_Stop(music_channel);
	OPENAL_Channel_Stop(music_channel2);
	music_channel = nullptr;
	music_channel2 = nullptr;
	music_resume = nullptr;

	auto releaseSound = [](OPENAL_BUFFER*& sound) {
		OPENAL_Sound_Release(sound);
		sound = nullptr;
	};
	auto releaseArray = [&releaseSound](OPENAL_BUFFER**& music, int count) {
		if (!music)
		{
			return;
		}
		for (int i = 0; i < count; ++i)
		{
			releaseSound(music[i]);
		}
		free(music);
		music = nullptr;
	};

	releaseSound(introductionmusic);
	releaseSound(intermissionmusic);
	releaseSound(minetownmusic);
	releaseSound(splashmusic);
	releaseSound(librarymusic);
	releaseSound(shopmusic);
	releaseSound(storymusic);
	releaseSound(herxmusic);
	releaseSound(templemusic);
	releaseSound(endgamemusic);
	releaseSound(escapemusic);
	releaseSound(devilmusic);
	releaseSound(sanctummusic);
	releaseSound(gnomishminesmusic);
	releaseSound(greatcastlemusic);
	releaseSound(sokobanmusic);
	releaseSound(caveslairmusic);
	releaseSound(bramscastlemusic);
	releaseSound(hamletmusic);
	releaseSound(tutorialmusic);
	releaseSound(gameovermusic);
	releaseSound(introstorymusic);
	releaseArray(minesmusic, NUMMINESMUSIC);
	releaseArray(swampmusic, NUMSWAMPMUSIC);
	releaseArray(labyrinthmusic, NUMLABYRINTHMUSIC);
	releaseArray(ruinsmusic, NUMRUINSMUSIC);
	releaseArray(underworldmusic, NUMUNDERWORLDMUSIC);
	releaseArray(hellmusic, NUMHELLMUSIC);
	releaseArray(minotaurmusic, NUMMINOTAURMUSIC);
	releaseArray(cavesmusic, NUMCAVESMUSIC);
	releaseArray(citadelmusic, NUMCITADELMUSIC);
	releaseArray(intromusic, NUMINTROMUSIC);
}

#endif

bool physfsSearchMusicToUpdate_helper_findModifiedMusic(uint32_t numMusic, const char* filenameTemplate)
{
	for ( int c = 0; c < numMusic; c++ )
	{
		snprintf(tempstr, 1000, filenameTemplate, c);
		if ( PHYSFS_getRealDir(tempstr) != nullptr )
		{
			std::string musicDir = PHYSFS_getRealDir(tempstr);
			if ( musicDir.compare("./") != 0 )
			{
				printlog("[PhysFS]: Found modified music in music/ directory, reloading music files...");
				return true;
			}
		}
	}

	return false;
}

const std::vector<std::string> themeMusic = {
	"music/introduction.ogg",
	"music/intermission.ogg",
	"music/minetown.ogg",
	"music/splash.ogg",
	"music/library.ogg",
	"music/shop.ogg",
	"music/herxboss.ogg",
	"music/temple.ogg",
	"music/endgame.ogg",
	"music/escape.ogg",
	"music/devil.ogg",
	"music/sanctum.ogg",
	"music/gnomishmines.ogg",
	"music/greatcastle.ogg",
	"music/sokoban.ogg",
	"music/caveslair.ogg",
	"music/bramscastle.ogg",
	"music/hamlet.ogg",
	"music/tutorial.ogg",
	"sound/Death.ogg",
	"sound/ui/StoryMusicV3.ogg",
	"sound/ensemble/ensemble1_drumV1.ogg",
	"sound/ensemble/ensemble1_fluteV1.ogg",
	"sound/ensemble/ensemble1_hornV1.ogg",
	"sound/ensemble/ensemble1_luteV1.ogg",
	"sound/ensemble/ensemble1_lyreV1.ogg",
	"sound/ensemble/ensemble1_tamboV1.ogg",
	"sound/ensemble/ensemble1_BEB_tier1_V1.ogg",
	"sound/ensemble/ensemble1_BEB_tier2_V1.ogg",
	"sound/ensemble/ensemble1_drum_combatV1.ogg",
	"sound/ensemble/ensemble1_flute_combatV1.ogg",
	"sound/ensemble/ensemble1_horn_combatV1.ogg",
	"sound/ensemble/ensemble1_lute_combatV1.ogg",
	"sound/ensemble/ensemble1_lyre_combatV1.ogg",
	"sound/ensemble/ensemble1_tambo_combatV1.ogg",
	"sound/ensemble/ensemble1_BEB_tier1_combatV1.ogg",
	"sound/ensemble/ensemble1_BEB_tier2_combatV1.ogg",
	/*"sound/ensemble/Trans1/ensemble1_drum_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_flute_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_horn_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_lute_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_lyre_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_tambo_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_tambo_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans1/ensemble1_tambo_Trans1_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_drum_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_flute_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_horn_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_lute_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_lyre_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_tambo_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_tambo_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans2/ensemble1_tambo_Trans2_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_drum_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_flute_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_horn_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_lute_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_lyre_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_tambo_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_tambo_Trans3_120_4-4_V1.ogg",
	"sound/ensemble/Trans3/ensemble1_tambo_Trans3_120_4-4_V1.ogg",*/
	"sound/ensemble/CombatEnd1/ensemble1_drum_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_flute_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_horn_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_lute_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_lyre_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_tambo_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_BEB_tier1_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd1/ensemble1_BEB_tier2_combat_End1_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_drum_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_flute_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_horn_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_lute_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_lyre_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_tambo_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_BEB_tier1_combat_End2_90_7-8.ogg",
	"sound/ensemble/CombatEnd2/ensemble1_BEB_tier2_combat_End2_90_7-8.ogg",
	/*"sound/ensemble/CombatEnd3/ensemble1_drum_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_flute_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_horn_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_lute_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_lyre_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_tambo_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_tambo_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd3/ensemble1_tambo_combat_End3_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_drum_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_flute_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_horn_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_lute_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_lyre_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_tambo_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_tambo_combat_End4_90_7-8.ogg",
	"sound/ensemble/CombatEnd4/ensemble1_tambo_combat_End4_90_7-8.ogg",*/
	"sound/ensemble/Trans4/ensemble1_drum_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_flute_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_horn_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_lute_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_lyre_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_tambo_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_BEB_tier1_Trans_120_4-4.ogg",
	"sound/ensemble/Trans4/ensemble1_BEB_tier2_Trans_120_4-4.ogg"
};

bool physfsSearchMusicToUpdate()
{
	if ( no_sound )
	{
		return false;
	}
#ifdef SOUND

	for ( auto it = themeMusic.begin(); it != themeMusic.end(); ++it )
	{
		std::string filename = *it;
		if ( PHYSFS_getRealDir(filename.c_str()) != nullptr )
		{
			std::string musicDir = PHYSFS_getRealDir(filename.c_str());
			if ( musicDir.compare("./") != 0 )
			{
				printlog("[PhysFS]: Found modified music in music/ directory, reloading music files...");
				return true;
			}
		}
	}

	int c;

	if ( physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMMINESMUSIC, "music/mines%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMSWAMPMUSIC, "music/swamp%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMLABYRINTHMUSIC, "music/labyrinth%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMRUINSMUSIC, "music/ruins%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMUNDERWORLDMUSIC, "music/underworld%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMHELLMUSIC, "music/hell%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMMINOTAURMUSIC, "music/minotaur%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMCAVESMUSIC, "music/caves%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMCITADELMUSIC, "music/citadel%02d.ogg")
		|| physfsSearchMusicToUpdate_helper_findModifiedMusic(NUMFORTRESSMUSIC, "music/fortress%02d.ogg") )
	{
		return true;
	}

	for ( c = 0; c < NUMINTROMUSIC; c++ )
	{
		if ( c == 0 )
		{
			strcpy(tempstr, "music/intro.ogg");
		}
		else
		{
			snprintf(tempstr, 1000, "music/intro%02d.ogg", c);
		}
		if ( PHYSFS_getRealDir(tempstr) != nullptr )
		{
			std::string musicDir = PHYSFS_getRealDir(tempstr);
			if ( musicDir.compare("./") != 0 )
			{
				printlog("[PhysFS]: Found modified music in music/ directory, reloading music files...");
				return true;
			}
		}
	}
#endif // SOUND
	return false;
}

#ifdef USE_FMOD
FMOD_RESULT physfsReloadMusic_helper_reloadMusicArray(uint32_t numMusic, const char* filenameTemplate, FMOD::Sound** musicArray, bool reloadAll)
{
	for ( int c = 0; c < numMusic; c++ )
	{
		snprintf(tempstr, 1000, filenameTemplate, c);
		if ( PHYSFS_getRealDir(tempstr) != nullptr )
		{
			std::string musicDir = PHYSFS_getRealDir(tempstr);
			if ( musicDir.compare("./") != 0 || reloadAll )
			{
				musicDir.append(PHYSFS_getDirSeparator()).append(tempstr);
				printlog("[PhysFS]: Loading music file %s...", tempstr);
				if ( musicArray )
				{
					musicArray[c]->release();
				}
                if ( musicPreload )
                {
                    fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &musicArray[c]); //TODO: Any other FMOD_MODEs should be used here? FMOD_SOFTWARE -> what now? FMOD_2D? LOOP?
                }
                else
                {
                    fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &musicArray[c]); //TODO: Any other FMOD_MODEs should be used here? FMOD_SOFTWARE -> what now? FMOD_2D? LOOP?
                }
                if (fmod_result != FMOD_OK)
                {
                    printlog("[PhysFS]: ERROR: Failed reloading music file \"%s\".");
                    return fmod_result;
                }
			}
		}
	}

	return FMOD_OK;
}
#endif

void physfsReloadMusic(bool &introMusicChanged, bool reloadAll) //TODO: This should probably return an error.
{
	if ( no_sound )
	{
		return;
	}
#ifdef USE_OPENAL
	(void)reloadAll;
	freeOpenALMusic();

	auto loadStream = [](const char* filename, OPENAL_BUFFER*& music) {
		if (!OPENAL_CreateStreamSound(filename, &music))
		{
			printlog("[OpenAL]: failed to register music stream '%s'\n", filename);
		}
	};
	auto loadArray = [&loadStream](OPENAL_BUFFER**& music, int count, const char* pattern) {
		music = static_cast<OPENAL_BUFFER**>(calloc(count, sizeof(OPENAL_BUFFER*)));
		for (int i = 0; i < count; ++i)
		{
			char filename[128];
			snprintf(filename, sizeof(filename), pattern, i);
			loadStream(filename, music[i]);
		}
	};

	loadStream(themeMusic[0].c_str(), introductionmusic);
	loadStream(themeMusic[1].c_str(), intermissionmusic);
	loadStream(themeMusic[2].c_str(), minetownmusic);
	loadStream(themeMusic[3].c_str(), splashmusic);
	loadStream(themeMusic[4].c_str(), librarymusic);
	loadStream(themeMusic[5].c_str(), shopmusic);
	loadStream(themeMusic[6].c_str(), herxmusic);
	loadStream(themeMusic[7].c_str(), templemusic);
	loadStream(themeMusic[8].c_str(), endgamemusic);
	loadStream(themeMusic[9].c_str(), escapemusic);
	loadStream(themeMusic[10].c_str(), devilmusic);
	loadStream(themeMusic[11].c_str(), sanctummusic);
	loadStream(themeMusic[12].c_str(), gnomishminesmusic);
	loadStream(themeMusic[13].c_str(), greatcastlemusic);
	loadStream(themeMusic[14].c_str(), sokobanmusic);
	loadStream(themeMusic[15].c_str(), caveslairmusic);
	loadStream(themeMusic[16].c_str(), bramscastlemusic);
	loadStream(themeMusic[17].c_str(), hamletmusic);
	loadStream(themeMusic[18].c_str(), tutorialmusic);
	loadStream(themeMusic[19].c_str(), gameovermusic);
	loadStream(themeMusic[20].c_str(), introstorymusic);
	loadArray(minesmusic, NUMMINESMUSIC, "music/mines%02d.ogg");
	loadArray(swampmusic, NUMSWAMPMUSIC, "music/swamp%02d.ogg");
	loadArray(labyrinthmusic, NUMLABYRINTHMUSIC, "music/labyrinth%02d.ogg");
	loadArray(ruinsmusic, NUMRUINSMUSIC, "music/ruins%02d.ogg");
	loadArray(underworldmusic, NUMUNDERWORLDMUSIC, "music/underworld%02d.ogg");
	loadArray(hellmusic, NUMHELLMUSIC, "music/hell%02d.ogg");
	loadArray(minotaurmusic, NUMMINOTAURMUSIC, "music/minotaur%02d.ogg");
	loadArray(cavesmusic, NUMCAVESMUSIC, "music/caves%02d.ogg");
	loadArray(citadelmusic, NUMCITADELMUSIC, "music/citadel%02d.ogg");
	intromusic = static_cast<OPENAL_BUFFER**>(calloc(NUMINTROMUSIC, sizeof(OPENAL_BUFFER*)));
	loadStream("music/intro.ogg", intromusic[0]);
	for (int i = 1; i < NUMINTROMUSIC; ++i)
	{
		char filename[128];
		snprintf(filename, sizeof(filename), "music/intro%02d.ogg", i);
		loadStream(filename, intromusic[i]);
	}

	introMusicChanged = true;
	printlog("[OpenAL]: registered game music streams\n");
	return;
#else
#ifdef SOUND
	int index = 0;
#ifdef USE_OPENAL
#define FMOD_System_CreateStream(A, B, C, D, E) OPENAL_CreateStreamSound(B, E) //TODO: If this is still needed, it's probably now broke!
#define FMOD_SOUND OPENAL_BUFFER
#define fmod_system 0
#define FMOD_SOFTWARE 0
#define FMOD_Sound_Release OPENAL_Sound_Release
	int fmod_result;
#endif
	bool ensembleNeedsUpdate = false;
	for ( auto it = themeMusic.begin(); it != themeMusic.end(); ++it )
	{
		std::string filename = *it;
		if ( PHYSFS_getRealDir(filename.c_str()) != nullptr )
		{
			std::string musicDir = PHYSFS_getRealDir(filename.c_str());
			if ( musicDir.compare("./") != 0 || reloadAll )
			{
				musicDir += PHYSFS_getDirSeparator() + filename;
				printlog("[PhysFS]: Loading music file %s...", filename.c_str());
				switch ( index )
				{
					case 0:
						if ( introductionmusic )
						{
							introductionmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &introductionmusic); //TODO: FMOD_SOFTWARE -> what now? FMOD_2D? FMOD_LOOP_NORMAL? More things? Something else?
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &introductionmusic); //TODO: FMOD_SOFTWARE -> what now? FMOD_2D? FMOD_LOOP_NORMAL? More things? Something else?
                        }
						break;
					case 1:
						if ( intermissionmusic )
						{
							intermissionmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &intermissionmusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &intermissionmusic);
                        }
						break;
					case 2:
						if ( minetownmusic )
						{
							minetownmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &minetownmusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &minetownmusic);
                        }
						break;
					case 3:
						if ( splashmusic )
						{
							splashmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &splashmusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &splashmusic);
                        }
						break;
					case 4:
						if ( librarymusic )
						{
							librarymusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &librarymusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &librarymusic);
                        }
						break;
					case 5:
						if ( shopmusic )
						{
							shopmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &shopmusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &shopmusic);
                        }
						break;
					case 6:
						if ( herxmusic )
						{
							herxmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &herxmusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &herxmusic);
                        }
						break;
					case 7:
						if ( templemusic )
						{
							templemusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &templemusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &templemusic);
                        }
						break;
					case 8:
						if ( endgamemusic )
						{
							endgamemusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &endgamemusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &endgamemusic);
                        }
						break;
					case 9:
						if ( escapemusic )
						{
							escapemusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &escapemusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &escapemusic);
                        }
						break;
					case 10:
						if ( devilmusic )
						{
							devilmusic->release();
						}
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &devilmusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &devilmusic);
                        }
						break;
					case 11:
						if ( sanctummusic )
						{
							sanctummusic->release();
                        }
                        if ( musicPreload )
                        {
                            fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &sanctummusic);
                        }
                        else
                        {
                            fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &sanctummusic);
                        }
						break;
					case 12:
						if ( gnomishminesmusic )
						{
							gnomishminesmusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &gnomishminesmusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &gnomishminesmusic);
						}
						break;
					case 13:
						if ( greatcastlemusic )
						{
							greatcastlemusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &greatcastlemusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &greatcastlemusic);
						}
						break;
					case 14:
						if ( sokobanmusic )
						{
							sokobanmusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &sokobanmusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &sokobanmusic);
						}
						break;
					case 15:
						if ( caveslairmusic )
						{
							caveslairmusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &caveslairmusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &caveslairmusic);
						}
						break;
					case 16:
						if ( bramscastlemusic )
						{
							bramscastlemusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &bramscastlemusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &bramscastlemusic);
						}
						break;
					case 17:
						if ( hamletmusic )
						{
							hamletmusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &hamletmusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &hamletmusic);
						}
						break;
					case 18:
						if ( tutorialmusic )
						{
							tutorialmusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &tutorialmusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &tutorialmusic);
						}
						break;
					case 19:
						if ( gameovermusic )
						{
							gameovermusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_DEFAULT, nullptr, &gameovermusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_DEFAULT, nullptr, &gameovermusic);
						}
						break;
					case 20:
						if ( introstorymusic )
						{
							introstorymusic->release();
						}
						if ( musicPreload )
						{
							fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_DEFAULT, nullptr, &introstorymusic);
						}
						else
						{
							fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_DEFAULT, nullptr, &introstorymusic);
						}
						break;
					default:
#ifdef USE_FMOD
#ifndef EDITOR
						if ( index >= 21 && index < 21 + NUMENSEMBLEMUSIC * 5 )
						{
#ifdef NINTENDO
							if ( !ensembleSounds.firstTimeSetup )
							{
								continue;
							}
#endif

							ensembleNeedsUpdate = true;
							int c = (index - 21) % NUMENSEMBLEMUSIC;
							FMOD_MODE flags = FMOD_3D | FMOD_LOOP_NORMAL | FMOD_NONBLOCKING;
#ifdef NINTENDO
							flags |= FMOD_NONBLOCKING;
#endif
							if ( index >= 21 + NUMENSEMBLEMUSIC * 0 && index < 21 + NUMENSEMBLEMUSIC * 1 )
							{
								fmod_result = ensembleSounds.exploreChannel[c] ? ensembleSounds.exploreChannel[c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.exploreSound[c] ? ensembleSounds.exploreSound[c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), flags, nullptr, &ensembleSounds.exploreSound[c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 1 && index < 21 + NUMENSEMBLEMUSIC * 2 )
							{
								fmod_result = ensembleSounds.combatChannel[c] ? ensembleSounds.combatChannel[c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatSound[c] ? ensembleSounds.combatSound[c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), flags, nullptr, &ensembleSounds.combatSound[c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 2 && index < 21 + NUMENSEMBLEMUSIC * 3 )
							{
								fmod_result = ensembleSounds.combatTransChannel[0][c] ? ensembleSounds.combatTransChannel[0][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatTransSound[0][c] ? ensembleSounds.combatTransSound[0][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), flags, nullptr, &ensembleSounds.combatTransSound[0][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 3 && index < 21 + NUMENSEMBLEMUSIC * 4 )
							{
								fmod_result = ensembleSounds.combatTransChannel[1][c] ? ensembleSounds.combatTransChannel[1][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatTransSound[1][c] ? ensembleSounds.combatTransSound[1][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), flags, nullptr, &ensembleSounds.combatTransSound[1][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 4 && index < 21 + NUMENSEMBLEMUSIC * 5 )
							{
								fmod_result = ensembleSounds.exploreTransChannel[3][c] ? ensembleSounds.exploreTransChannel[3][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.exploreTransSound[3][c] ? ensembleSounds.exploreTransSound[3][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), flags, nullptr, &ensembleSounds.exploreTransSound[3][c]);
							}
							/*else if ( index >= 21 + NUMENSEMBLEMUSIC * 2 && index < 21 + NUMENSEMBLEMUSIC * 3 )
							{
								fmod_result = ensembleSounds.exploreTransChannel[0][c] ? ensembleSounds.exploreTransChannel[0][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.exploreTransSound[0][c] ? ensembleSounds.exploreTransSound[0][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.exploreTransSound[0][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 3 && index < 21 + NUMENSEMBLEMUSIC * 4 )
							{
								fmod_result = ensembleSounds.exploreTransChannel[1][c] ? ensembleSounds.exploreTransChannel[1][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.exploreTransSound[1][c] ? ensembleSounds.exploreTransSound[1][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.exploreTransSound[1][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 4 && index < 21 + NUMENSEMBLEMUSIC * 5 )
							{
								fmod_result = ensembleSounds.exploreTransChannel[2][c] ? ensembleSounds.exploreTransChannel[2][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.exploreTransSound[2][c] ? ensembleSounds.exploreTransSound[2][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.exploreTransSound[2][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 5 && index < 21 + NUMENSEMBLEMUSIC * 6 )
							{
								fmod_result = ensembleSounds.combatTransChannel[0][c] ? ensembleSounds.combatTransChannel[0][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatTransSound[0][c] ? ensembleSounds.combatTransSound[0][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.combatTransSound[0][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 6 && index < 21 + NUMENSEMBLEMUSIC * 7 )
							{
								fmod_result = ensembleSounds.combatTransChannel[1][c] ? ensembleSounds.combatTransChannel[1][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatTransSound[1][c] ? ensembleSounds.combatTransSound[1][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.combatTransSound[1][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 7 && index < 21 + NUMENSEMBLEMUSIC * 8 )
							{
								fmod_result = ensembleSounds.combatTransChannel[2][c] ? ensembleSounds.combatTransChannel[2][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatTransSound[2][c] ? ensembleSounds.combatTransSound[2][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.combatTransSound[2][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 8 && index < 21 + NUMENSEMBLEMUSIC * 9 )
							{
								fmod_result = ensembleSounds.combatTransChannel[3][c] ? ensembleSounds.combatTransChannel[3][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.combatTransSound[3][c] ? ensembleSounds.combatTransSound[3][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.combatTransSound[3][c]);
							}
							else if ( index >= 21 + NUMENSEMBLEMUSIC * 9 && index < 21 + NUMENSEMBLEMUSIC * 10 )
							{
								fmod_result = ensembleSounds.exploreTransChannel[3][c] ? ensembleSounds.exploreTransChannel[3][c]->stop() : FMOD_OK;
								fmod_result = ensembleSounds.exploreTransSound[3][c] ? ensembleSounds.exploreTransSound[3][c]->release() : FMOD_OK;
								fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_3D | FMOD_LOOP_NORMAL, nullptr, &ensembleSounds.exploreTransSound[3][c]);
							}*/
						}
#endif
#endif
						break;
				}
				if ( FMODErrorCheck() )
				{
					printlog("[PhysFS]: ERROR: Failed reloading music file \"%s\".", filename.c_str());
					//TODO: Handle error? Abort? Fling pies at people?
				}
			}
		}
		++index;
	}

	int c;
	FMOD::Sound** music = nullptr;

	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMMINESMUSIC, "music/mines%02d.ogg", minesmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload mines music array.");
		//TODO: Handle error? Abort? Fling pies at people?
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMSWAMPMUSIC, "music/swamp%02d.ogg", swampmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload swamp music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMLABYRINTHMUSIC, "music/labyrinth%02d.ogg", labyrinthmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload labyrinth music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMRUINSMUSIC, "music/ruins%02d.ogg", ruinsmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload ruins music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMUNDERWORLDMUSIC, "music/underworld%02d.ogg", underworldmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload underworld music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMHELLMUSIC, "music/hell%02d.ogg", hellmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload hell music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMMINOTAURMUSIC, "music/minotaur%02d.ogg", minotaurmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload minotaur music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMCAVESMUSIC, "music/caves%02d.ogg", cavesmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload caves music array.");
	}
	if (FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMCITADELMUSIC, "music/citadel%02d.ogg", citadelmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload citadel music array.");
	}
	if ( FMOD_OK != (fmod_result = physfsReloadMusic_helper_reloadMusicArray(NUMFORTRESSMUSIC, "music/fortress%02d.ogg", fortressmusic, reloadAll)) )
	{
		printlog("[PhysFS]: Failed to reload fortress music array.");
	}

	bool introChanged = false;

	for ( c = 0; c < NUMINTROMUSIC; c++ )
	{
		if ( c == 0 )
		{
			strcpy(tempstr, "music/intro.ogg");
		}
		else
		{
			snprintf(tempstr, 1000, "music/intro%02d.ogg", c);
		}
		if ( PHYSFS_getRealDir(tempstr) != nullptr )
		{
			std::string musicDir = PHYSFS_getRealDir(tempstr);
			if ( musicDir.compare("./") != 0 || reloadAll )
			{
				musicDir.append(PHYSFS_getDirSeparator()).append(tempstr);
				printlog("[PhysFS]: Loading music file %s...", tempstr);
				music = intromusic;
				if ( music )
				{
					music[c]->release();
				}
                if ( musicPreload )
                {
                    fmod_result = fmod_system->createSound(musicDir.c_str(), FMOD_2D, nullptr, &music[c]);
                }
                else
                {
                    fmod_result = fmod_system->createStream(musicDir.c_str(), FMOD_2D, nullptr, &music[c]);
                }
                introChanged = true;
                if (fmod_result != FMOD_OK)
                {
                    printlog("[PhysFS]: ERROR: Failed reloading music file \"%s\".");
                    break; //TODO: Handle the error?
                }
			}
		}
	}

#ifdef USE_FMOD
#ifndef EDITOR
	if ( ensembleNeedsUpdate && !ensembleSounds.firstTimeSetup ) // only setup here on modded reloads
	{
		ensembleSounds.setup();
	}
#endif
#endif

	introMusicChanged = introChanged; // use this variable outside of this function to start playing a new fresh list of tracks in the main menu.
#ifdef USE_OPENAL
#undef FMOD_System_CreateStream
#undef FMOD_SOUND
#undef fmod_system
#undef FMOD_SOFTWARE
#undef FMOD_Sound_Release
#endif

#endif // SOUND
#endif // USE_OPENAL
}

void gamemodsUnloadCustomThemeMusic()
{
#ifdef SOUND
#ifdef USE_OPENAL
	auto releaseSound = [](OPENAL_BUFFER*& sound) {
		OPENAL_Sound_Release(sound);
		sound = nullptr;
	};
	releaseSound(gnomishminesmusic);
	releaseSound(greatcastlemusic);
	releaseSound(sokobanmusic);
	releaseSound(caveslairmusic);
	releaseSound(bramscastlemusic);
	releaseSound(hamletmusic);
#else
	// free custom music slots, not used by official music assets.
	if ( gnomishminesmusic )
	{
		gnomishminesmusic->release();
		gnomishminesmusic = nullptr;
	}
	if ( greatcastlemusic )
	{
		greatcastlemusic->release();
		greatcastlemusic = nullptr;
	}
	if ( sokobanmusic )
	{
		sokobanmusic->release();
		sokobanmusic = nullptr;
	}
	if ( caveslairmusic )
	{
		caveslairmusic->release();
		caveslairmusic = nullptr;
	}
	if ( bramscastlemusic )
	{
		bramscastlemusic->release();
		bramscastlemusic = nullptr;
	}
	if ( hamletmusic )
	{
		hamletmusic->release();
		hamletmusic = nullptr;
	}
#endif // USE_OPENAL
#endif // !SOUND
}
