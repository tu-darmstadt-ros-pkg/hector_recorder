cmake_minimum_required(VERSION 3.8)
project(hector_recorder_msgs)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# find dependencies
find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(std_msgs REQUIRED)
find_package(builtin_interfaces REQUIRED)

rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/RecorderStatus.msg"
  "msg/TopicInfo.msg"
  "msg/BagInfo.msg"
  "msg/BagTopicInfo.msg"
  "srv/StartRecording.srv"
  "srv/StopRecording.srv"
  "srv/PauseRecording.srv"
  "srv/ResumeRecording.srv"
  "srv/SplitBag.srv"
  "srv/ApplyConfig.srv"
  "srv/SaveConfig.srv"
  "srv/GetAvailableTopics.srv"
  "srv/ListBags.srv"
  "srv/GetBagDetails.srv"
  "srv/DeleteBag.srv"
  DEPENDENCIES std_msgs builtin_interfaces)

ament_export_dependencies(rosidl_default_runtime)

# Ensure interfaces are installed
install(
  DIRECTORY msg srv
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
