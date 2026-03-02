cmake_minimum_required(VERSION 3.14)
project(turbotoken C)

option(TURBOTOKEN_BUILD_EXAMPLES "Build example programs" ON)
option(TURBOTOKEN_BUILD_TESTS "Build test programs" ON)
option(TURBOTOKEN_BUILD_FROM_SOURCE "Build libturbotoken from Zig source" OFF)

# --- Find or build the turbotoken library -----------------------------------

if(TURBOTOKEN_BUILD_FROM_SOURCE)
    find_program(ZIG_EXECUTABLE zig REQUIRED)

    set(TURBOTOKEN_LIB_DIR "${CMAKE_BINARY_DIR}/zig-out/lib")
    set(TURBOTOKEN_LIB "${TURBOTOKEN_LIB_DIR}/libturbotoken${CMAKE_STATIC_LIBRARY_SUFFIX}")

    add_custom_command(
        OUTPUT "${TURBOTOKEN_LIB}"
        COMMAND "${ZIG_EXECUTABLE}" build -Doptimize=ReleaseFast
                --prefix "${CMAKE_BINARY_DIR}/zig-out"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../.."
        COMMENT "Building libturbotoken from Zig source"
    )
    add_custom_target(turbotoken_zig_build DEPENDS "${TURBOTOKEN_LIB}")

    add_library(turbotoken_lib STATIC IMPORTED GLOBAL)
    set_target_properties(turbotoken_lib PROPERTIES
        IMPORTED_LOCATION "${TURBOTOKEN_LIB}"
    )
    add_dependencies(turbotoken_lib turbotoken_zig_build)
else()
    find_library(TURBOTOKEN_LIBRARY
        NAMES turbotoken
        HINTS "${CMAKE_CURRENT_SOURCE_DIR}/../../zig-out/lib"
              "${CMAKE_INSTALL_PREFIX}/lib"
    )
    if(NOT TURBOTOKEN_LIBRARY)
        message(FATAL_ERROR
            "libturbotoken not found. Either:\n"
            "  1) Run 'zig build' in the repo root first, or\n"
            "  2) Set -DTURBOTOKEN_BUILD_FROM_SOURCE=ON")
    endif()

    add_library(turbotoken_lib STATIC IMPORTED GLOBAL)
    set_target_properties(turbotoken_lib PROPERTIES
        IMPORTED_LOCATION "${TURBOTOKEN_LIBRARY}"
    )
endif()

# --- Public include directory -----------------------------------------------

set(TURBOTOKEN_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../include")

# --- Imported target with interface -----------------------------------------

add_library(turbotoken::turbotoken INTERFACE IMPORTED GLOBAL)
target_link_libraries(turbotoken::turbotoken INTERFACE turbotoken_lib)
target_include_directories(turbotoken::turbotoken INTERFACE
    "$<BUILD_INTERFACE:${TURBOTOKEN_INCLUDE_DIR}>"
    "$<INSTALL_INTERFACE:include>"
)

# --- Examples ---------------------------------------------------------------

if(TURBOTOKEN_BUILD_EXAMPLES)
    add_executable(encode_example examples/encode_example.c)
    target_link_libraries(encode_example PRIVATE turbotoken::turbotoken)

    add_executable(count_example examples/count_example.c)
    target_link_libraries(count_example PRIVATE turbotoken::turbotoken)

    add_executable(chat_example examples/chat_example.c)
    target_link_libraries(chat_example PRIVATE turbotoken::turbotoken)
endif()

# --- Tests ------------------------------------------------------------------

if(TURBOTOKEN_BUILD_TESTS)
    enable_testing()

    add_executable(test_encode tests/test_encode.c)
    target_link_libraries(test_encode PRIVATE turbotoken::turbotoken)

    add_test(NAME turbotoken_encode COMMAND test_encode)
endif()

# --- Install ----------------------------------------------------------------

install(FILES "${TURBOTOKEN_INCLUDE_DIR}/turbotoken.h"
        DESTINATION include)

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/turbotoken.pc.in"
    "${CMAKE_BINARY_DIR}/turbotoken.pc"
    @ONLY
)

install(FILES "${CMAKE_BINARY_DIR}/turbotoken.pc"
        DESTINATION lib/pkgconfig)
