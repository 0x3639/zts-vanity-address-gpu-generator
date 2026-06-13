cmake_minimum_required(VERSION 3.18)

project(zts_vanity_address_generator LANGUAGES CXX CUDA)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

add_executable(znn-vanity-cuda
  src/main.cu
)

target_compile_options(znn-vanity-cuda PRIVATE
  $<$<COMPILE_LANGUAGE:CUDA>:-O3 --use_fast_math --expt-relaxed-constexpr>
)
