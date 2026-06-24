#ifndef HECTOR_RECORDER_TERMINAL_UI_HPP
#define HECTOR_RECORDER_TERMINAL_UI_HPP

#include "hector_recorder/modified/recorder_impl.hpp"
#include "hector_recorder/utils.h"
#include "hector_recorder_msgs/msg/recorder_status.hpp"
#include "hector_recorder_msgs/msg/topic_info.hpp"
#include "hector_recorder_msgs/srv/apply_config.hpp"
#include "hector_recorder_msgs/srv/get_available_topics.hpp"
#include "hector_recorder_msgs/srv/get_available_services.hpp"
#include "hector_recorder_msgs/srv/get_config.hpp"
#include "hector_recorder_msgs/srv/get_recorder_info.hpp"
#include "hector_recorder_msgs/srv/pause_recording.hpp"
#include "hector_recorder_msgs/srv/resume_recording.hpp"
#include "hector_recorder_msgs/srv/save_config.hpp"
#include "hector_recorder_msgs/srv/split_bag.hpp"
#include "hector_recorder_msgs/srv/start_recording.hpp"
#include "hector_recorder_msgs/srv/stop_recording.hpp"
#include "hector_recorder_msgs/srv/list_bags.hpp"
#include "hector_recorder_msgs/srv/get_bag_details.hpp"
#include "hector_recorder_msgs/srv/delete_bag.hpp"
#include "rclcpp/rclcpp.hpp"
#include "rosbag2_cpp/writers/sequential_writer.hpp"
#include "rosbag2_storage/storage_options.hpp"
#include "rosbag2_transport/record_options.hpp"
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <ncurses.h>
#include <string>
#include <vector>

namespace hector_recorder
{

class TerminalUI : public rclcpp::Node
{
public:
  TerminalUI( const hector_recorder::CustomOptions &custom_options,
              const rosbag2_storage::StorageOptions &storage_options,
              const rosbag2_transport::RecordOptions &record_options );

  ~TerminalUI();

private:
  void initializeRecorder();
  void initializeUI();
  void cleanupUI();
  void startRecording();
  void stopRecording();
  void updateUI();
  void updateGeneralInfo();
  void updateTable();
  std::vector<std::pair<std::string, TopicInformation>>
  sortTopics( const std::unordered_map<std::string, TopicInformation> &topics_info );
  void adjustColumnWidths();
  void distributeRemainingWidth( size_t longest_topic_name, size_t longest_topic_type );
  void renderTable();
  void renderHeaders();
  void renderSeperatorLine();
  void renderTopicRow( const std::pair<std::string, TopicInformation> &topic );
  void publishRecorderStatus();
  void initializeServices();

  // Service callbacks
  void onStartRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Response> response );
  void onStopRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::StopRecording::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::StopRecording::Response> response );
  void onPauseRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::PauseRecording::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::PauseRecording::Response> response );
  void onResumeRecording(
      const std::shared_ptr<hector_recorder_msgs::srv::ResumeRecording::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::ResumeRecording::Response> response );
  void onSplitBag( const std::shared_ptr<hector_recorder_msgs::srv::SplitBag::Request>,
                   std::shared_ptr<hector_recorder_msgs::srv::SplitBag::Response> response );
  void onApplyConfig(
      const std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Response> response );
  void onSaveConfig(
      const std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Response> response );
  void onGetAvailableTopics(
      const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Response> response );
  void onGetAvailableServices(
      const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableServices::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::GetAvailableServices::Response> response );
  void onGetConfig(
      const std::shared_ptr<hector_recorder_msgs::srv::GetConfig::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::GetConfig::Response> response );
  void onGetRecorderInfo(
      const std::shared_ptr<hector_recorder_msgs::srv::GetRecorderInfo::Request>,
      std::shared_ptr<hector_recorder_msgs::srv::GetRecorderInfo::Response> response );
  void onListBags(
      const std::shared_ptr<hector_recorder_msgs::srv::ListBags::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::ListBags::Response> response );
  void onGetBagDetails(
      const std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Response> response );
  void onDeleteBag(
      const std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Request> request,
      std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Response> response );

  std::unique_ptr<hector_recorder::RecorderImpl> recorder_;
  CustomOptions custom_options_;
  rosbag2_storage::StorageOptions storage_options_;
  rosbag2_transport::RecordOptions record_options_;
  std::string raw_output_uri_; // Original unresolved output path from config
  size_t ui_topics_max_length_;
  size_t ui_topics_type_max_length_;
  std::vector<std::pair<std::string, TopicInformation>> sorted_topics_;
  std::vector<std::string> headers_;
  std::vector<int> column_widths_;
  int max_width_;
  int row_;
  int total_width_;
  std::mutex data_mutex_;
  rclcpp::TimerBase::SharedPtr ui_refresh_timer_;
  rclcpp::TimerBase::SharedPtr status_pub_timer_;
  std::string config_path_;
  bool publish_status_;
  ThrottleConfigMap throttle_configs_;

  rclcpp::Publisher<hector_recorder_msgs::msg::RecorderStatus>::SharedPtr status_pub_;

  // Service servers for remote control
  rclcpp::Service<hector_recorder_msgs::srv::StartRecording>::SharedPtr start_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::StopRecording>::SharedPtr stop_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::PauseRecording>::SharedPtr pause_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::ResumeRecording>::SharedPtr resume_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::SplitBag>::SharedPtr split_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::ApplyConfig>::SharedPtr config_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::SaveConfig>::SharedPtr save_config_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetAvailableTopics>::SharedPtr topics_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetAvailableServices>::SharedPtr services_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetConfig>::SharedPtr get_config_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetRecorderInfo>::SharedPtr get_info_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::ListBags>::SharedPtr list_bags_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::GetBagDetails>::SharedPtr get_bag_details_srv_;
  rclcpp::Service<hector_recorder_msgs::srv::DeleteBag>::SharedPtr delete_bag_srv_;

  WINDOW *generalInfoWin_;
  WINDOW *tableWin_;
};

std::string formatMemory( uint64_t bytes );
std::string rateToString( double rate );
std::string bandwidthToString( double bandwidth );

} // namespace hector_recorder

#endif // HECTOR_RECORDER_TERMINAL_UI_HPP
