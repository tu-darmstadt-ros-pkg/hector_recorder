#ifndef TERMINAL_UI_HPP
#define TERMINAL_UI_HPP

#include "hector_recorder/modified/recorder_impl.hpp"
#include "hector_recorder/utils.h"
#include "hector_recorder_msgs/msg/recorder_status.hpp"
#include "hector_recorder_msgs/msg/topic_info.hpp"
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
  void drawBorders();
  void cleanupUI();
  void startRecording();
  void stopRecording();
  void updateUI();
  void updateGeneralInfo();
  void updateWarnings();
  void updateSystemResources();
  void updateTable();
  std::vector<std::pair<std::string, TopicInformation>>
  sortTopics( const std::unordered_map<std::string, TopicInformation> &topics_info );
  void adjustColumnWidths();
  void distributeRemainingWidth( size_t longest_topic_name, size_t longest_topic_type );
  void renderTable();
  void renderHeaders();
  void renderSeperatorLine();
  void renderTopicRow( const std::pair<std::string, TopicInformation> &topic );
  std::tuple<std::string, int, std::string> getTopicDetails( const std::string &topic_name );
  void publishRecorderStatus();

  std::unique_ptr<hector_recorder::RecorderImpl> recorder_;
  rosbag2_storage::StorageOptions storage_options_;
  rosbag2_transport::RecordOptions record_options_;
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

  rclcpp::Publisher<hector_recorder_msgs::msg::RecorderStatus>::SharedPtr status_pub_;

  WINDOW *generalInfoWin_;
  WINDOW *warningsWin_;
  WINDOW *resourcesWin_;
  WINDOW *tableWin_;
};

std::string formatMemory( uint64_t bytes );
std::string rateToString( double rate );
std::string bandwidthToString( double bandwidth );

} // namespace hector_recorder

#endif // TERMINAL_UI_HPP
