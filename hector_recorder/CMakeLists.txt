cmake_minimum_required(VERSION 3.16)
project(hector_recorder)

# Find dependencies
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rosbag2_cpp REQUIRED)
find_package(rosbag2_transport REQUIRED)
find_package(rosbag2_storage REQUIRED)
find_package(rosbag2_interfaces REQUIRED)
find_package(hector_recorder_msgs REQUIRED)
find_package(fmt REQUIRED)
find_package(Curses REQUIRED)
find_package(yaml-cpp REQUIRED)

set(LIBRARY_NAME hector_recorder_lib)
# set(EXECUTABLE_NAME server)

# Add library
add_library(
  ${LIBRARY_NAME}
  SHARED
  src/arg_parser.cpp
  src/modified/recorder_impl.cpp
  src/utils.cpp
  src/config_yaml.cpp
  src/service_handlers.cpp
  src/recorder_node.cpp
)

# Include directories
target_include_directories(
  ${LIBRARY_NAME}
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include/${PROJECT_NAME}>
)

include_directories(include include/modified)

# Link library
target_link_libraries(
  ${LIBRARY_NAME}
  PUBLIC
    rclcpp::rclcpp
    rosbag2_cpp::rosbag2_cpp
    rosbag2_transport::rosbag2_transport
    rosbag2_storage::rosbag2_storage
    ${rosbag2_interfaces_TARGETS}
    ${hector_recorder_msgs_TARGETS}
    fmt::fmt
    yaml-cpp::yaml-cpp
)

add_executable(record src/main.cpp src/terminal_ui.cpp)

target_link_libraries(
  record
  ${LIBRARY_NAME}
  rclcpp::rclcpp
  fmt::fmt
  ${CURSES_LIBRARIES}
  yaml-cpp
)

# Headless recorder executable (no ncurses dependency)
add_executable(record_headless src/main_headless.cpp)

target_link_libraries(record_headless ${LIBRARY_NAME} rclcpp::rclcpp fmt::fmt yaml-cpp)

# Install
install(DIRECTORY include/ DESTINATION include/${PROJECT_NAME})

install(DIRECTORY config DESTINATION share/${PROJECT_NAME}/)

install(
  TARGETS ${LIBRARY_NAME}
  EXPORT export_${PROJECT_NAME}
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin
)

ament_export_targets(export_${PROJECT_NAME} HAS_LIBRARY_TARGET)

# Export information to downstream packages
ament_export_dependencies(
        rclcpp
        rosbag2_cpp
        fmt
)

# Install environment hooks
ament_environment_hooks(env_hooks/50.scripts.bash.in)

# Install directories
install(DIRECTORY scripts env_hooks DESTINATION share/${PROJECT_NAME})

if(BUILD_TESTING)
  find_package(ament_cmake_gtest REQUIRED)
  ament_add_gtest(test_utils test/test_utils.cpp)
  target_link_libraries(test_utils ${LIBRARY_NAME} yaml-cpp)

  # rtest-based integration tests for RecorderNode service layer
  find_package(ament_cmake_gmock QUIET)
  find_package(GTest CONFIG QUIET COMPONENTS GTest GMock)
  find_package(rtest QUIET)
  # GTestConfig.cmake (libgtest-dev) only loads the GMock targets if libgmock-dev is installed
  if(NOT TARGET GTest::gmock)
    message(WARNING "GTest::gmock not found (install libgmock-dev), skipping test_recorder_node")
  endif()
  if(ament_cmake_gmock_FOUND AND GTest_FOUND AND TARGET GTest::gmock AND rtest_FOUND)
    test_tools_add_doubles(
      ${LIBRARY_NAME}
      AMENT_DEPENDENCIES
        ${rclcpp_TARGETS}
        ${rosbag2_cpp_TARGETS}
        ${rosbag2_transport_TARGETS}
        ${rosbag2_storage_TARGETS}
        ${rosbag2_interfaces_TARGETS}
        ${hector_recorder_msgs_TARGETS}
        yaml-cpp
        fmt::fmt
    )

    target_include_directories(
      ${LIBRARY_NAME}_test_doubles
      PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    )

    ament_add_gmock(test_recorder_node test/test_recorder_node.cpp)
    target_include_directories(
      test_recorder_node
      PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/test
    )
    target_link_libraries(test_recorder_node ${PROJECT_NAME}::${LIBRARY_NAME}_test_doubles)
  endif()
endif()

ament_package()

install(TARGETS record record_headless DESTINATION lib/${PROJECT_NAME})
