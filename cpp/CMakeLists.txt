cmake_minimum_required(VERSION 3.14)
project(turbotoken-cpp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(TURBOTOKEN_CPP_HEADER_ONLY "Use header-only mode (no compiled library)" OFF)
option(TURBOTOKEN_CPP_BUILD_TESTS "Build test programs" ON)
option(TURBOTOKEN_BUILD_FROM_SOURCE "Build libturbotoken from Zig source" OFF)

# --- Find or build the C library -------------------------------------------

if(TURBOTOKEN_BUILD_FROM_SOURCE)
    find_program(ZIG_EXECUTABLE zig REQUIRED)

    set(TURBOTOKEN_LIB_DIR "${CMAKE_BINARY_DIR}/zig-out/lib")
    set(TURBOTOKEN_LIB "${TURBOTOKEN_LIB_DIR}/libturbotoken${CMAKE_STATIC_LIBRARY_SUFFIX}")

    add_custom_command(
        OUTPUT "${TURBOTOKEN_LIB}"
        COMMAND "${ZIG_EXECUTABLE}" build -Doptimize=ReleaseFast
                --prefix "${CMAKE_BINARY_DIR}/zig-out"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
        COMMENT "Building libturbotoken from Zig source"
    )
    add_custom_target(turbotoken_zig_build DEPENDS "${TURBOTOKEN_LIB}")

    add_library(turbotoken_c STATIC IMPORTED GLOBAL)
    set_target_properties(turbotoken_c PROPERTIES
        IMPORTED_LOCATION "${TURBOTOKEN_LIB}"
    )
    add_dependencies(turbotoken_c turbotoken_zig_build)
else()
    find_library(TURBOTOKEN_LIBRARY
        NAMES turbotoken
        HINTS "${CMAKE_CURRENT_SOURCE_DIR}/../zig-out/lib"
              "${CMAKE_INSTALL_PREFIX}/lib"
    )
    if(NOT TURBOTOKEN_LIBRARY)
        message(FATAL_ERROR
            "libturbotoken not found. Either:\n"
            "  1) Run 'zig build' in the repo root first, or\n"
            "  2) Set -DTURBOTOKEN_BUILD_FROM_SOURCE=ON")
    endif()

    add_library(turbotoken_c STATIC IMPORTED GLOBAL)
    set_target_properties(turbotoken_c PROPERTIES
        IMPORTED_LOCATION "${TURBOTOKEN_LIBRARY}"
    )
endif()

set(TURBOTOKEN_C_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../include")

# --- C++ library ------------------------------------------------------------

if(TURBOTOKEN_CPP_HEADER_ONLY)
    add_library(turbotoken-cpp INTERFACE)
    target_compile_definitions(turbotoken-cpp INTERFACE TURBOTOKEN_HEADER_ONLY=1)
    target_include_directories(turbotoken-cpp INTERFACE
        "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
        "$<BUILD_INTERFACE:${TURBOTOKEN_C_INCLUDE_DIR}>"
        "$<INSTALL_INTERFACE:include>"
    )
    target_link_libraries(turbotoken-cpp INTERFACE turbotoken_c)
else()
    add_library(turbotoken-cpp STATIC
        src/encoding.cpp
        src/registry.cpp
        src/rank_cache.cpp
    )
    target_include_directories(turbotoken-cpp PUBLIC
        "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
        "$<BUILD_INTERFACE:${TURBOTOKEN_C_INCLUDE_DIR}>"
        "$<INSTALL_INTERFACE:include>"
    )
    target_link_libraries(turbotoken-cpp PUBLIC turbotoken_c)
endif()

add_library(turbotoken::turbotoken-cpp ALIAS turbotoken-cpp)

# --- Tests ------------------------------------------------------------------

if(TURBOTOKEN_CPP_BUILD_TESTS)
    enable_testing()

    add_executable(encoding_test tests/encoding_test.cpp)
    target_link_libraries(encoding_test PRIVATE turbotoken-cpp)

    add_test(NAME turbotoken_cpp_encoding COMMAND encoding_test)
endif()

# --- Install ----------------------------------------------------------------

install(DIRECTORY include/turbotoken DESTINATION include)
install(FILES "${TURBOTOKEN_C_INCLUDE_DIR}/turbotoken.h" DESTINATION include)

if(NOT TURBOTOKEN_CPP_HEADER_ONLY)
    install(TARGETS turbotoken-cpp
            ARCHIVE DESTINATION lib
            LIBRARY DESTINATION lib)
endif()
