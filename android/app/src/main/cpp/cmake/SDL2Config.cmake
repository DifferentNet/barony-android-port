# OpenAL Soft asks find_package(SDL2) even when SDL is already part of the
# enclosing build. Expose that existing target without searching the host.
if(TARGET SDL2::SDL2)
    set(SDL2_FOUND TRUE)
else()
    set(SDL2_FOUND FALSE)
endif()
