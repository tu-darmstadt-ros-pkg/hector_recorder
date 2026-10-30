cmake_minimum_required(VERSION 3.16)
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
  URI RQml.Recorder
  VERSION 1.0
  RESOURCE_PREFIX /qt/qml
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
  OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/RQml/Recorder"
)

target_include_directories(rqml_recorder_plugin PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(rqml_recorder_plugin PRIVATE Qt6::Core Qt6::Qml Qt6::Network)
target_link_libraries(
  rqml_recorder_plugin
  PUBLIC
    rclcpp::rclcpp
    rosbag2_cpp::rosbag2_cpp
    rosbag2_storage::rosbag2_storage
    ${rosgraph_msgs_TARGETS}
)

# Install the QML module so rqml can find it at runtime
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/RQml" DESTINATION share/${PROJECT_NAME})

# Install plugin QML files
install(DIRECTORY qml DESTINATION share/${PROJECT_NAME})

# Register the plugin resource
ament_index_register_resource(rqml_plugin CONTENT_FILE rqml_plugins.yaml.in)

# Register QML import path so rqml can find the RQml.Recorder module
ament_environment_hooks(register_qml_module.dsv.in)

if(BUILD_TESTING)
  find_package(Qt6 REQUIRED COMPONENTS QuickTest)
  find_package(qml6_ros2_plugin REQUIRED)

  # Build mock Ros2 and RQml.Recorder modules in the build tree.
  # Ros2 types (Subscription, ServiceClient, ...) are C++ mocks registered in the test
  # harness (test_plugins.cpp), shared with rqml_default_plugins. RQml.Recorder overrides
  # the C++ engines of this package with QML files.
  set(MOCK_ROS2_DIR "${CMAKE_CURRENT_BINARY_DIR}/test_mocks/Ros2")
  set(MOCK_RQML_RECORDER_DIR "${CMAKE_CURRENT_BINARY_DIR}/test_mocks/RQml/Recorder")
  file(MAKE_DIRECTORY "${MOCK_ROS2_DIR}")
  file(MAKE_DIRECTORY "${MOCK_RQML_RECORDER_DIR}")

  file(GLOB _MOCK_ROS2_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks/Ros2/*")
  foreach(mock_file ${_MOCK_ROS2_FILES})
    get_filename_component(_fname "${mock_file}" NAME)
    file(CREATE_LINK "${mock_file}" "${MOCK_ROS2_DIR}/${_fname}" COPY_ON_ERROR SYMBOLIC)
  endforeach()

  file(GLOB _MOCK_RECORDER_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks/RQml/Recorder/*")
  foreach(mock_file ${_MOCK_RECORDER_FILES})
    get_filename_component(_fname "${mock_file}" NAME)
    file(CREATE_LINK "${mock_file}" "${MOCK_RQML_RECORDER_DIR}/${_fname}" COPY_ON_ERROR SYMBOLIC)
  endforeach()

  add_executable(test_plugins test/test_plugins.cpp test/mock_ros2.cpp test/mock_classes.cpp)
  target_compile_definitions(
    test_plugins
    PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test"
  )
  target_link_libraries(
    test_plugins
    PRIVATE Qt6::QuickTest Qt6::Qml Qt6::Quick qml6_ros2_plugin::qml6_ros2_plugin
  )
  set(TEST_RESULT_DIR "${CMAKE_BINARY_DIR}/test_results/${PROJECT_NAME}")
  ament_add_test(
    test_plugins
    COMMAND $<TARGET_FILE:test_plugins>
        -import "${CMAKE_CURRENT_BINARY_DIR}/test_mocks"
        -import "${CMAKE_CURRENT_SOURCE_DIR}/qml"
        -junitxml
        -o "${TEST_RESULT_DIR}/test_plugins.xml"
    ENV QT_QPA_PLATFORM=offscreen
    RESULT_FILE "${TEST_RESULT_DIR}/test_plugins.xml"
    TIMEOUT 300
  )
endif()

ament_package()
