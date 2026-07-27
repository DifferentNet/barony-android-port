#include <SDL.h>
#include <GLES3/gl3.h>

#include <cmath>
#include <unordered_map>

namespace {

using ControllerMap = std::unordered_map<SDL_JoystickID, SDL_GameController*>;

const char* gl_string(GLenum name) {
    const auto* value = glGetString(name);
    return value == nullptr ? "unknown" : reinterpret_cast<const char*>(value);
}

void open_controller(int device_index, ControllerMap& controllers) {
    if (!SDL_IsGameController(device_index)) {
        SDL_Log("BARONY_ANDROID_CONTROLLER_IGNORED device_index=%d", device_index);
        return;
    }

    SDL_GameController* controller = SDL_GameControllerOpen(device_index);
    if (controller == nullptr) {
        SDL_LogError(
            SDL_LOG_CATEGORY_INPUT,
            "BARONY_ANDROID_CONTROLLER_OPEN_FAILED device_index=%d error=%s",
            device_index,
            SDL_GetError()
        );
        return;
    }

    SDL_Joystick* joystick = SDL_GameControllerGetJoystick(controller);
    const SDL_JoystickID instance_id = SDL_JoystickInstanceID(joystick);
    if (controllers.find(instance_id) != controllers.end()) {
        SDL_GameControllerClose(controller);
        return;
    }

    controllers[instance_id] = controller;
    SDL_Log(
        "BARONY_ANDROID_CONTROLLER_CONNECTED instance=%d name=%s",
        static_cast<int>(instance_id),
        SDL_GameControllerName(controller) == nullptr
            ? "unknown"
            : SDL_GameControllerName(controller)
    );
}

void close_controllers(ControllerMap& controllers) {
    for (auto& entry : controllers) {
        SDL_GameControllerClose(entry.second);
    }
    controllers.clear();
}

} // namespace

int main(int, char**) {
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
    SDL_LogSetAllPriority(SDL_LOG_PRIORITY_INFO);
    SDL_Log("BARONY_ANDROID_SMOKE_READY");

    constexpr Uint32 subsystems =
        SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER;
    if (SDL_Init(subsystems) != 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "SDL_Init failed: %s", SDL_GetError());
        return 1;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

    SDL_Window* window = SDL_CreateWindow(
        "Barony Android Port",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        1280,
        720,
        SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN_DESKTOP | SDL_WINDOW_ALLOW_HIGHDPI
    );
    if (window == nullptr) {
        SDL_LogError(
            SDL_LOG_CATEGORY_APPLICATION,
            "SDL_CreateWindow failed: %s",
            SDL_GetError()
        );
        SDL_Quit();
        return 1;
    }

    SDL_GLContext context = SDL_GL_CreateContext(window);
    if (context == nullptr || SDL_GL_MakeCurrent(window, context) != 0) {
        SDL_LogError(
            SDL_LOG_CATEGORY_APPLICATION,
            "OpenGL ES context setup failed: %s",
            SDL_GetError()
        );
        if (context != nullptr) {
            SDL_GL_DeleteContext(context);
        }
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    SDL_GL_SetSwapInterval(1);
    SDL_Log(
        "BARONY_ANDROID_GL_ES_READY vendor=%s renderer=%s version=%s",
        gl_string(GL_VENDOR),
        gl_string(GL_RENDERER),
        gl_string(GL_VERSION)
    );

    ControllerMap controllers;
    const int joystick_count = SDL_NumJoysticks();
    for (int device_index = 0; device_index < joystick_count; ++device_index) {
        open_controller(device_index, controllers);
    }

    bool running = true;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                case SDL_QUIT:
                    running = false;
                    break;
                case SDL_KEYDOWN:
                    if (event.key.keysym.sym == SDLK_ESCAPE
                        || event.key.keysym.sym == SDLK_AC_BACK) {
                        running = false;
                    }
                    break;
                case SDL_CONTROLLERDEVICEADDED:
                    open_controller(event.cdevice.which, controllers);
                    break;
                case SDL_CONTROLLERDEVICEREMOVED: {
                    const auto controller = controllers.find(event.cdevice.which);
                    if (controller != controllers.end()) {
                        SDL_Log(
                            "BARONY_ANDROID_CONTROLLER_DISCONNECTED instance=%d",
                            static_cast<int>(event.cdevice.which)
                        );
                        SDL_GameControllerClose(controller->second);
                        controllers.erase(controller);
                    }
                    break;
                }
                case SDL_CONTROLLERBUTTONDOWN:
                case SDL_CONTROLLERBUTTONUP: {
                    const auto button = static_cast<SDL_GameControllerButton>(
                        event.cbutton.button
                    );
                    const char* name = SDL_GameControllerGetStringForButton(button);
                    SDL_Log(
                        "BARONY_ANDROID_CONTROLLER_BUTTON instance=%d button=%s state=%s",
                        static_cast<int>(event.cbutton.which),
                        name == nullptr ? "unknown" : name,
                        event.type == SDL_CONTROLLERBUTTONDOWN ? "down" : "up"
                    );
                    break;
                }
                case SDL_CONTROLLERAXISMOTION:
                    if (std::abs(static_cast<int>(event.caxis.value)) >= 16000) {
                        const auto axis = static_cast<SDL_GameControllerAxis>(event.caxis.axis);
                        const char* name = SDL_GameControllerGetStringForAxis(axis);
                        SDL_Log(
                            "BARONY_ANDROID_CONTROLLER_AXIS instance=%d axis=%s value=%d",
                            static_cast<int>(event.caxis.which),
                            name == nullptr ? "unknown" : name,
                            static_cast<int>(event.caxis.value)
                        );
                    }
                    break;
                case SDL_APP_WILLENTERBACKGROUND:
                    SDL_Log("BARONY_ANDROID_APP_BACKGROUND");
                    break;
                case SDL_APP_DIDENTERFOREGROUND:
                    SDL_Log("BARONY_ANDROID_APP_FOREGROUND");
                    break;
                default:
                    break;
            }
        }

        int drawable_width = 0;
        int drawable_height = 0;
        SDL_GL_GetDrawableSize(window, &drawable_width, &drawable_height);
        glViewport(0, 0, drawable_width, drawable_height);
        glClearColor(0.025F, 0.075F, 0.18F, 1.0F);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        SDL_GL_SwapWindow(window);
        SDL_Delay(8);
    }

    SDL_Log("BARONY_ANDROID_SMOKE_EXIT");
    close_controllers(controllers);
    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
