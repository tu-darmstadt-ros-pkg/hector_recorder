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
  URI RQml.Recorder
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
  OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/RQml/Recorder"
)

target_include_directories(rqml_recorder_plugin PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(rqml_recorder_plugin PRIVATE Qt6::Core Qt6::Qml Qt6::Network)
ament_target_dependencies(rqml_recorder_plugin PUBLIC rclcpp rosbag2_cpp rosbag2_storage rosgraph_msgs)

# Install the QML module so rqml can find it at runtime
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/RQml"
  DESTINATION share/${PROJECT_NAME})

# Install plugin QML files
install(DIRECTORY qml DESTINATION share/${PROJECT_NAME})

# Register the plugin resource
ament_index_register_resource(rqml_plugin CONTENT_FILE rqml_plugins.yaml.in)

# Register QML import path so rqml can find the RQml.Recorder module
ament_environment_hooks(register_qml_module.dsv.in)

if(BUILD_TESTING)
  find_package(Qt6 REQUIRED COMPONENTS QuickTest)
  find_package(qml6_ros2_plugin REQUIRED)

  # Build mock Ros2 and RQml.Recorder modules in the build tree
  set(MOCK_ROS2_DIR "${CMAKE_CURRENT_BINARY_DIR}/test_mocks/Ros2")
  set(MOCK_RQML_RECORDER_DIR "${CMAKE_CURRENT_BINARY_DIR}/test_mocks/RQml/Recorder")
  file(MAKE_DIRECTORY "${MOCK_ROS2_DIR}")
  file(MAKE_DIRECTORY "${MOCK_RQML_RECORDER_DIR}")

  file(GLOB _MOCK_ROS2_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks/Ros2/*")
  foreach(mock_file ${_MOCK_ROS2_FILES})
    get_filename_component(_fname "${mock_file}" NAME)
    file(CREATE_LINK
            "${mock_file}" "${MOCK_ROS2_DIR}/${_fname}"
            COPY_ON_ERROR SYMBOLIC)
  endforeach()

  file(GLOB _MOCK_RECORDER_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks/RQml/Recorder/*")
  foreach(mock_file ${_MOCK_RECORDER_FILES})
    get_filename_component(_fname "${mock_file}" NAME)
    file(CREATE_LINK
            "${mock_file}" "${MOCK_RQML_RECORDER_DIR}/${_fname}"
            COPY_ON_ERROR SYMBOLIC)
  endforeach()

  add_executable(test_plugins test/test_plugins.cpp)
  target_compile_definitions(test_plugins
    PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test"
  )
  target_link_libraries(test_plugins
    PRIVATE
    Qt6::QuickTest
    Qt6::Qml
    Qt6::Quick
    qml6_ros2_plugin::qml6_ros2_plugin
  )
  # Generate wrapper script that sets QML2_IMPORT_PATH with test_mocks first
  # and filters out the installed rqml_recorder C++ plugin path so the QML
  # mock module takes priority.
  set(TEST_WRAPPER "${CMAKE_CURRENT_BINARY_DIR}/run_test_plugins.sh")
  file(WRITE "${TEST_WRAPPER}"
    "#!/bin/bash\n"
    "# Filter installed rqml_recorder from QML2_IMPORT_PATH, prepend test mocks\n"
    "MOCK_PATH=\"${CMAKE_CURRENT_BINARY_DIR}/test_mocks\"\n"
    "FILTERED=\"\"\n"
    "IFS=':' read -ra PARTS <<< \"$QML2_IMPORT_PATH\"\n"
    "for p in \"\${PARTS[@]}\"; do\n"
    "  case \"$p\" in *rqml_recorder*) ;; *) FILTERED=\"\${FILTERED:+$FILTERED:}$p\" ;; esac\n"
    "done\n"
    "export QML2_IMPORT_PATH=\"\${MOCK_PATH}\${FILTERED:+:$FILTERED}\"\n"
    "# Filter snap core library paths from LD_LIBRARY_PATH to avoid glibc conflicts\n"
    "if [ -n \"$LD_LIBRARY_PATH\" ]; then\n"
    "  FILTERED_LD=\"\"\n"
    "  IFS=':' read -ra LD_PARTS <<< \"$LD_LIBRARY_PATH\"\n"
    "  for p in \"\${LD_PARTS[@]}\"; do\n"
    "    case \"$p\" in /snap/core*) ;; *) FILTERED_LD=\"\${FILTERED_LD:+$FILTERED_LD:}$p\" ;; esac\n"
    "  done\n"
    "  export LD_LIBRARY_PATH=\"$FILTERED_LD\"\n"
    "fi\n"
    "exec \"$@\"\n"
  )
  file(CHMOD "${TEST_WRAPPER}" PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE
  )

  set(TEST_RESULT_DIR "${CMAKE_BINARY_DIR}/test_results/${PROJECT_NAME}")
  ament_add_test(
    test_plugins
    COMMAND "${TEST_WRAPPER}" $<TARGET_FILE:test_plugins>
        -import "${CMAKE_CURRENT_BINARY_DIR}/test_mocks"
        -import "${CMAKE_CURRENT_SOURCE_DIR}/qml"
        -junitxml
        -o "${TEST_RESULT_DIR}/test_plugins.xml"
    RESULT_FILE "${TEST_RESULT_DIR}/test_plugins.xml"
  )
endif()

ament_package()
