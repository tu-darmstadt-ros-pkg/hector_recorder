#ifndef HECTOR_RECORDER_RECORDER_NODE_HPP
#define HECTOR_RECORDER_RECORDER_NODE_HPP

#include "hector_recorder/modified/recorder_impl.hpp"
#include "hector_recorder/utils.h"
#include "hector_recorder_msgs/msg/recorder_status.hpp"
#include "hector_recorder_msgs/msg/topic_info.hpp"
#include "hector_recorder_msgs/srv/start_recording.hpp"
#include "hector_recorder_msgs/srv/stop_recording.hpp"
#include "hector_recorder_msgs/srv/pause_recording.hpp"
#include "hector_recorder_msgs/srv/resume_recording.hpp"
#include "hector_recorder_msgs/srv/split_bag.hpp"
#include "hector_recorder_msgs/srv/apply_config.hpp"
#include "hector_recorder_msgs/srv/save_config.hpp"
#include "hector_recorder_msgs/srv/get_available_topics.hpp"
#include "hector_recorder_msgs/srv/list_bags.hpp"
#include "hector_recorder_msgs/srv/get_bag_details.hpp"
#include "hector_recorder_msgs/srv/delete_bag.hpp"
#include "rclcpp/rclcpp.hpp"
#include "rosbag2_cpp/writers/sequential_writer.hpp"
#include "rosbag2_storage/storage_options.hpp"
#include "rosbag2_transport/record_options.hpp"
#include <memory>
#include <mutex>
#include <string>

namespace hector_recorder
{

/// Headless recorder node with ROS 2 service interface for remote control.
/// Unlike TerminalUI, this node has no ncurses dependency and is designed
/// to be controlled entirely via ROS 2 services.
class RecorderNode : public rclcpp::Node
{
public:
  RecorderNode( const CustomOptions &custom_options,
                const rosbag2_storage::StorageOptions &storage_options,
                const rosbag2_transport::RecordOptions &record_options,
                bool auto_start = false );

  ~RecorderNode();

private:
  void initializeRecorder();
  void publishStatus();

  // Service callbacks
  void onStartRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Response> response );
  void onStopRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::StopRecording::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::StopRecording::Response> response );
  void onPauseRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::PauseRecording::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::PauseRecording::Response> response );
  void onResumeRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::ResumeRecording::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::ResumeRecording::Response> response );
  void onSplitBag(
      const std::shared_ptr<hector_recorder_msgs::srv::SplitBag::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::SplitBag::Response> response );
  void onApplyConfig(
      const std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Response> response );
  void onSaveConfig(
      const std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Response> response );
  void onGetAvailableTopics(
      const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Response> response );
  void onListBags(
      const std::shared_ptr<hector_recorder_msgs::srv::ListBags::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::ListBags::Response> response );
  void onGetBagDetails(
      const std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Response> response );
  void onDeleteBag(
      const std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Response> response );

  std::unique_ptr<RecorderImpl> recorder_;
  CustomOptions custom_options_;
  rosbag2_storage::StorageOptions storage_options_;
  rosbag2_transport::RecordOptions record_options_;
  std::string raw_output_uri_; // Original unresolved output path from config

  rclcpp::Publisher<hector_recorder_msgs::msg::RecorderStatus>::SharedPtr status_pub_;
  rclcpp::TimerBase::SharedPtr status_timer_;

  rclcpp::Service<hector_recorder_msgs::srv::StartRecording>::SharedPtr start_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::StopRecording>::SharedPtr stop_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::PauseRecording>::SharedPtr pause_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::ResumeRecording>::SharedPtr resume_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::SplitBag>::SharedPtr split_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::ApplyConfig>::SharedPtr config_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::SaveConfig>::SharedPtr save_config_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetAvailableTopics>::SharedPtr topics_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::ListBags>::SharedPtr list_bags_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetBagDetails>::SharedPtr get_bag_details_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::DeleteBag>::SharedPtr delete_bag_srv_;

  std::mutex data_mutex_;
};

} // namespace hector_recorder

#endif // HECTOR_RECORDER_RECORDER_NODE_HPP
