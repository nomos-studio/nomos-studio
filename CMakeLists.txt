# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
# SPDX-License-Identifier: EPL-2.0
cmake_minimum_required(VERSION 3.25)

project(nomos-studio-system
    VERSION 0.1.0
    DESCRIPTION "nomos-studio system build — orchestrates the full C++ component stack"
    HOMEPAGE_URL "https://github.com/nomos-studio/nomos-studio"
    LANGUAGES NONE)

include(ExternalProject)
include(CTest)

# ---------------------------------------------------------------------------
# components.lock parser
#
# Line format: <component>  <sha>  <remote>
# Sets NOMOS_SHA_<id> and NOMOS_REMOTE_<id> in the calling scope, where <id>
# is the C identifier form of <component> (hyphens become underscores).
# ---------------------------------------------------------------------------
function(nomos_read_lockfile lockfile)
    file(STRINGS "${lockfile}" _lines REGEX "^[a-zA-Z]")
    foreach(_line ${_lines})
        string(REGEX MATCH
            "^([a-zA-Z][a-zA-Z0-9_-]*)[ \t]+([0-9a-f]{40})[ \t]+(git[^ \t\r\n]+)"
            _ "${_line}")
        if(CMAKE_MATCH_1)
            string(MAKE_C_IDENTIFIER "${CMAKE_MATCH_1}" _id)
            set("NOMOS_SHA_${_id}"    "${CMAKE_MATCH_2}" PARENT_SCOPE)
            set("NOMOS_REMOTE_${_id}" "${CMAKE_MATCH_3}" PARENT_SCOPE)
        endif()
    endforeach()
endfunction()

nomos_read_lockfile("${CMAKE_CURRENT_SOURCE_DIR}/components.lock")

# ---------------------------------------------------------------------------
# NOMOS_SRC_ROOT — parent directory of all component repos.
# Default: the directory containing this file (src/nomos-studio) → src/
# ---------------------------------------------------------------------------
set(NOMOS_SRC_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH
    "Root of the nomos-studio checkout tree (parent of all component repos)")
get_filename_component(NOMOS_SRC_ROOT "${NOMOS_SRC_ROOT}" ABSOLUTE)
message(STATUS "nomos-studio: component root = ${NOMOS_SRC_ROOT}")

option(NOMOS_FORCE_FETCH
    "Ignore local checkouts and resolve all components from components.lock SHAs"
    OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(_COMMON_ARGS
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
    "-DFETCHCONTENT_UPDATES_DISCONNECTED=ON"
)

# ---------------------------------------------------------------------------
# nomos_add_component(<name> [DEPENDS <dep>...] [CMAKE_ARGS <arg>...])
#
# Registers one C++ component as an ExternalProject. Prefers the local
# checkout at ${NOMOS_SRC_ROOT}/<name>; falls back to the locked SHA from
# components.lock. DEPENDS controls build ordering (not CMake-level linkage —
# each component fetches its own copy of shared deps via FetchContent with
# the SOURCE_DIR overrides supplied in CMAKE_ARGS).
# ---------------------------------------------------------------------------
function(nomos_add_component name)
    cmake_parse_arguments(NAC "" "" "DEPENDS;CMAKE_ARGS" ${ARGN})
    string(MAKE_C_IDENTIFIER "${name}" _id)

    set(_src "${NOMOS_SRC_ROOT}/${name}")
    set(_bin "${CMAKE_CURRENT_BINARY_DIR}/${name}-build")
    set(_args ${_COMMON_ARGS} ${NAC_CMAKE_ARGS})

    if(NOT NOMOS_FORCE_FETCH AND IS_DIRECTORY "${_src}" AND EXISTS "${_src}/CMakeLists.txt")
        ExternalProject_Add("${name}"
            SOURCE_DIR      "${_src}"
            BINARY_DIR      "${_bin}"
            CMAKE_ARGS      ${_args}
            BUILD_ALWAYS    OFF
            INSTALL_COMMAND ""
            DEPENDS         ${NAC_DEPENDS}
        )
        message(STATUS "nomos-studio: ${name} → local checkout (${_src})")
    elseif(NOMOS_SHA_${_id})
        ExternalProject_Add("${name}"
            GIT_REPOSITORY  "${NOMOS_REMOTE_${_id}}"
            GIT_TAG         "${NOMOS_SHA_${_id}}"
            GIT_SHALLOW     FALSE
            BINARY_DIR      "${_bin}"
            CMAKE_ARGS      ${_args}
            BUILD_ALWAYS    OFF
            INSTALL_COMMAND ""
            DEPENDS         ${NAC_DEPENDS}
        )
        message(STATUS "nomos-studio: ${name} → SHA ${NOMOS_SHA_${_id}}")
    else()
        message(FATAL_ERROR
            "nomos_add_component(${name}): no local checkout at '${_src}' "
            "and no SHA in components.lock")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Component DAG.
#
# Build order: nomos-rt, edn-cpp, nomos-topology → kairos, kairos-grid, aion
#
# Each component already supports SOURCE_DIR overrides via -D flags to avoid
# re-fetching shared deps across independent ExternalProject builds.
# ---------------------------------------------------------------------------

# Tier 1: no inter-component deps
nomos_add_component(nomos-rt
    CMAKE_ARGS
        "-DTXLOG_CPP_DIR=${NOMOS_SRC_ROOT}/txlog/cpp"
)
nomos_add_component(edn-cpp)
nomos_add_component(nomos-topology)

# Tier 2: depend on Tier 1
nomos_add_component(kairos
    DEPENDS nomos-rt nomos-topology
    CMAKE_ARGS
        "-DNOMOS_RT_DIR=${NOMOS_SRC_ROOT}/nomos-rt"
        "-DNOMOS_TOPOLOGY_SRC_DIR=${NOMOS_SRC_ROOT}/nomos-topology"
)

nomos_add_component(kairos-grid
    DEPENDS nomos-topology
    CMAKE_ARGS
        "-DNOMOS_TOPOLOGY_SRC_DIR=${NOMOS_SRC_ROOT}/nomos-topology"
)

nomos_add_component(aion
    DEPENDS nomos-rt
    CMAKE_ARGS
        "-DNOMOS_RT_DIR=${NOMOS_SRC_ROOT}/nomos-rt"
)

# ---------------------------------------------------------------------------
# Aggregate REUSE compliance target — runs reuse lint in each component's
# source directory, with --root to avoid changing the working directory.
# ---------------------------------------------------------------------------
find_program(REUSE_EXECUTABLE reuse)
if(REUSE_EXECUTABLE)
    set(_ALL_REPOS
        aion alembic bwosc ctrl-tree edn-cpp kairos kairos-grid
        maps nomos-maths nomos-rt nomos-studio.el nomos-tauri
        nomos-topology nomos_beam nous protomatter txlog
    )
    set(_reuse_cmds)
    foreach(_repo ${_ALL_REPOS})
        set(_src "${NOMOS_SRC_ROOT}/${_repo}")
        if(IS_DIRECTORY "${_src}")
            list(APPEND _reuse_cmds
                COMMAND ${CMAKE_COMMAND} -E echo "=== ${_repo} ==="
                COMMAND ${REUSE_EXECUTABLE} --root "${_src}" lint
            )
        endif()
    endforeach()

    add_custom_target(lint-reuse-all
        ${_reuse_cmds}
        COMMENT "Checking REUSE compliance for all nomos-studio repos"
        VERBATIM
    )
endif()
