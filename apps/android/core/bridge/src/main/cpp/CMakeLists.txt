cmake_minimum_required(VERSION 3.22.1)

project(litter_ghostty_jni LANGUAGES CXX)

add_library(ghostty SHARED IMPORTED)
set_target_properties(
    ghostty
    PROPERTIES
        IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libghostty.so"
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

add_library(litter_ghostty_jni SHARED ghostty_jni.cpp)

target_compile_features(litter_ghostty_jni PRIVATE cxx_std_17)
target_include_directories(litter_ghostty_jni PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(litter_ghostty_jni PRIVATE ghostty EGL GLESv3 android log)
