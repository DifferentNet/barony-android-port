#pragma once

enum class AndroidTouchLayoutMode
{
	Menu = 0,
	Gameplay = 1,
	UI = 2
};

void androidUpdateTouchLayoutMode(AndroidTouchLayoutMode mode);
