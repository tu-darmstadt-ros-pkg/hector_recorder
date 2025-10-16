cmake_minimum_required(VERSION 3.8)
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
add_library(${LIBRARY_NAME} SHARED 
        src/arg_parser.cpp
        src/modified/recorder_impl.cpp
        src/utils.cpp   
        )

# Include directories
target_include_directories(${LIBRARY_NAME} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include/${PROJECT_NAME}>)

include_directories(include include/modified)

# Link library
ament_target_dependencies(${LIBRARY_NAME} PUBLIC
        rclcpp
        rosbag2_cpp
        rosbag2_transport
        rosbag2_storage
        rosbag2_interfaces
        hector_recorder_msgs
        )        

add_executable(record 
        src/main.cpp
        src/terminal_ui.cpp
)

ament_target_dependencies(record
  rclcpp
  hector_recorder_msgs
  fmt
)

target_link_libraries(record
  ${LIBRARY_NAME}
  ${rclcpp_LIBRARIES}
  fmt::fmt
  ${CURSES_LIBRARIES}
  yaml-cpp
)

# Install
install(
        DIRECTORY include/
        DESTINATION include/${PROJECT_NAME}
)

install (DIRECTORY config
        DESTINATION share/${PROJECT_NAME}/
)

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
        rosbag2_cpp)


# Install environment hooks
ament_environment_hooks(env_hooks/50.scripts.bash.in)

# Install directories
install(DIRECTORY
  scripts
  env_hooks
  DESTINATION share/${PROJECT_NAME}
)

ament_package()

install(TARGETS record
        DESTINATION lib/${PROJECT_NAME})