#include "android_dlc_bridge.hpp"

#ifdef __ANDROID__

#include "main.hpp"
#include "game.hpp"

#include <SDL.h>
#include <physfs.h>

#include <algorithm>
#include <cctype>
#include <string>

namespace
{
	constexpr const char* DLC_UNLOCK_FILE = "dlc.unlock";
	constexpr PHYSFS_sint64 DLC_UNLOCK_MAX_BYTES = 4096;

	std::string trim(const std::string& value)
	{
		auto first = std::find_if_not(value.begin(), value.end(),
			[](unsigned char character) { return std::isspace(character) != 0; });
		auto last = std::find_if_not(value.rbegin(), value.rend(),
			[](unsigned char character) { return std::isspace(character) != 0; }).base();
		if ( first >= last )
		{
			return {};
		}
		return std::string(first, last);
	}

	void logEntitlement(const char* pack, bool enabled, const char* source)
	{
		SDL_Log("BARONY_ANDROID_DLC_ENTITLEMENT pack=%s enabled=%d source=%s",
			pack, enabled ? 1 : 0, source);
	}
}

void androidApplyDLCEntitlements()
{
	const bool keyPack1 = enabledDLCPack1;
	const bool keyPack2 = enabledDLCPack2;
	const bool keyPack3 = enabledDLCPack3;
	bool steamPack1 = false;
	bool steamPack2 = false;
	bool steamPack3 = false;

	PHYSFS_File* file = PHYSFS_openRead(DLC_UNLOCK_FILE);
	if ( file )
	{
		const PHYSFS_sint64 length = PHYSFS_fileLength(file);
		if ( length >= 0 && length <= DLC_UNLOCK_MAX_BYTES )
		{
			std::string contents(static_cast<size_t>(length), '\0');
			const PHYSFS_sint64 read = length > 0
				? PHYSFS_readBytes(file, contents.data(), static_cast<PHYSFS_uint64>(length))
				: 0;
			if ( read == length )
			{
				bool format1 = false;
				bool parsedPack1 = false;
				bool parsedPack2 = false;
				bool parsedPack3 = false;
				size_t position = 0;
				while ( position <= contents.size() )
				{
					const size_t end = contents.find_first_of("\r\n", position);
					const std::string line = trim(contents.substr(position,
						end == std::string::npos ? std::string::npos : end - position));
					if ( line == "format=1" )
					{
						format1 = true;
					}
					else if ( !line.empty() && line.front() != '#' )
					{
						if ( line == "mythsandoutcasts" )
						{
							parsedPack1 = true;
						}
						else if ( line == "legendsandpariahs" )
						{
							parsedPack2 = true;
						}
						else if ( line == "desertersanddisciples" )
						{
							parsedPack3 = true;
						}
						else
						{
							SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
								"BARONY_ANDROID_DLC_ENTITLEMENT_IGNORED reason=unknown_entry");
						}
					}
					if ( end == std::string::npos )
					{
						break;
					}
					position = end + 1;
					if ( position < contents.size()
						&& contents[end] == '\r' && contents[position] == '\n' )
					{
						++position;
					}
				}
				if ( format1 )
				{
					steamPack1 = parsedPack1;
					steamPack2 = parsedPack2;
					steamPack3 = parsedPack3;
				}
				else
				{
					SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
						"BARONY_ANDROID_DLC_ENTITLEMENT_IGNORED reason=missing_format");
				}
			}
			else
			{
				SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
					"BARONY_ANDROID_DLC_ENTITLEMENT_IGNORED reason=read_failed");
			}
		}
		else
		{
			SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
				"BARONY_ANDROID_DLC_ENTITLEMENT_IGNORED reason=invalid_size");
		}
		PHYSFS_close(file);
	}

	enabledDLCPack1 = enabledDLCPack1 || steamPack1;
	enabledDLCPack2 = enabledDLCPack2 || steamPack2;
	enabledDLCPack3 = enabledDLCPack3 || steamPack3;

	logEntitlement("mythsandoutcasts", enabledDLCPack1,
		keyPack1 ? "key-file" : (steamPack1 ? "steam-cached-ticket" : "none"));
	logEntitlement("legendsandpariahs", enabledDLCPack2,
		keyPack2 ? "key-file" : (steamPack2 ? "steam-cached-ticket" : "none"));
	logEntitlement("desertersanddisciples", enabledDLCPack3,
		keyPack3 ? "key-file" : (steamPack3 ? "steam-cached-ticket" : "none"));
}

#else

void androidApplyDLCEntitlements()
{
}

#endif
