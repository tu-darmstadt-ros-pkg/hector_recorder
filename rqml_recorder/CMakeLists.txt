cmake_minimum_required(VERSION 3.15)
project(rqml_recorder)

find_package(ament_cmake REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Qml Network)
find_package(rclcpp REQUIRED)
find_package(rosbag2_cpp REQUIRED)
find_package(rosbag2_storage REQUIRED)
find_package(rosgraph_msgs REQUIRED)

qt_standard_project_setup()

# Build the QML module with the PresetStore C++ type
qt_add_qml_module(rqml_recorder_plugin
  URI RqmlRecorder
  VERSION 1.0
  SOURCES
    src/preset_store.hpp
    src/preset_store.cpp
    src/bag_transfer.hpp
    src/bag_transfer.cpp
    src/local_bag_scanner.hpp
    src/local_bag_scanner.cpp
    src/bag_player_engine.hpp
    src/bag_player_engine.cpp
    src/bag_recorder_engine.hpp
    src/bag_recorder_engine.cpp
  OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/RqmlRecorder"
)

target_include_directories(rqml_recorder_plugin PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(rqml_recorder_plugin PRIVATE Qt6::Core Qt6::Qml Qt6::Network)
ament_target_dependencies(rqml_recorder_plugin PUBLIC rclcpp rosbag2_cpp rosbag2_storage rosgraph_msgs)

# Install the QML module so rqml can find it at runtime
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/RqmlRecorder"
  DESTINATION lib/qt6/qml)

# Install plugin QML files
install(DIRECTORY qml DESTINATION share/${PROJECT_NAME})

# Register the plugin resource
ament_index_register_resource(rqml_plugin CONTENT_FILE rqml_plugins.yaml.in)

# Register QML import path so rqml can find the RqmlRecorder module
ament_environment_hooks(register_qml_module.dsv.in)

ament_package()
