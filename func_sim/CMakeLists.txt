cmake_minimum_required(VERSION 3.10)
project(tt_branch_pred)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_BUILD_TYPE Debug)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g")

add_executable(func_sim
    ./src/func_sim.cpp
)

target_include_directories(func_sim PRIVATE
    ./include
)

set_target_properties(func_sim PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ./build
)