#ifndef HECTOR_RECORDER_SERVICE_HANDLERS_H
#define HECTOR_RECORDER_SERVICE_HANDLERS_H

#include "hector_recorder/utils.h"

#include "hector_recorder_msgs/msg/bag_info.hpp"
#include "hector_recorder_msgs/msg/bag_topic_info.hpp"
#include "hector_recorder_msgs/msg/recorder_status.hpp"

#include <memory>
#include <string>
#include <vector>

namespace hector_recorder
{
class RecorderImpl;

// ========================================================================
// Shared service handler helpers (used by both RecorderNode and TerminalUI)
// ========================================================================

/// Populate a RecorderStatus message from the current recorder state.
void fillRecorderStatus( hector_recorder_msgs::msg::RecorderStatus &status_msg,
                         RecorderImpl *recorder, const CustomOptions &custom_options,
                         const rosbag2_storage::StorageOptions &storage_options,
                         rclcpp::Node *node );

/// Handle StartRecording service: resolve output, create recorder, start.
void handleStartRecording( std::unique_ptr<RecorderImpl> &recorder,
                           rosbag2_storage::StorageOptions &storage_options,
                           const rosbag2_transport::RecordOptions &record_options,
                           const CustomOptions &custom_options,
                           const std::string &raw_output_uri,
                           const std::string &request_output_dir,
                           const std::string &request_recorded_by, rclcpp::Node *node,
                           bool &out_success, std::string &out_message,
                           std::string &out_bag_path );

/// Handle StopRecording service: stop and reset recorder.
void handleStopRecording( std::unique_ptr<RecorderImpl> &recorder,
                          const rosbag2_storage::StorageOptions &storage_options,
                          bool &out_success, std::string &out_message,
                          std::string &out_bag_path );

/// Handle ApplyConfig service: parse YAML, optionally restart.
void handleApplyConfig( std::unique_ptr<RecorderImpl> &recorder, CustomOptions &custom_options,
                        rosbag2_transport::RecordOptions &record_options,
                        rosbag2_storage::StorageOptions &storage_options,
                        std::string &raw_output_uri, const std::string &config_yaml,
                        bool restart, rclcpp::Node *node, bool &out_success,
                        std::string &out_message, std::string &out_active_config_yaml );

/// Handle SaveConfig service: write YAML string to file.
void handleSaveConfig( const std::string &config_yaml, const std::string &file_path,
                       bool &out_success, std::string &out_message );

/// Handle GetAvailableTopics service: query node for all topics.
void handleGetAvailableTopics( rclcpp::Node *node, std::vector<std::string> &out_topics,
                               std::vector<std::string> &out_types );

/// Handle GetAvailableServices service: query node for non-infrastructure services.
void handleGetAvailableServices( rclcpp::Node *node, std::vector<std::string> &out_services,
                                 std::vector<std::string> &out_types );

/// Handle GetConfig service: serialize current config to YAML.
void handleGetConfig( const CustomOptions &custom_options,
                      const rosbag2_transport::RecordOptions &record_options,
                      const rosbag2_storage::StorageOptions &storage_options,
                      const std::string &raw_output_uri, std::string &out_config_yaml );

/// Handle GetRecorderInfo service: return static recorder metadata.
void handleGetRecorderInfo( const CustomOptions &custom_options, std::string &out_hostname,
                            std::string &out_recorded_by, std::string &out_config_path );

/// Handle ListBags service: scan directory for rosbag2 bags.
void handleListBags( const std::string &path,
                     const rosbag2_storage::StorageOptions &storage_options,
                     std::vector<hector_recorder_msgs::msg::BagInfo> &out_bags,
                     bool &out_success, std::string &out_message );

/// Handle GetBagDetails service: read per-topic info from a bag.
void handleGetBagDetails( const std::string &bag_path,
                          hector_recorder_msgs::msg::BagInfo &out_info,
                          std::vector<hector_recorder_msgs::msg::BagTopicInfo> &out_topics,
                          bool &out_success, std::string &out_message );

/// Handle DeleteBag service: delete a bag directory.
void handleDeleteBag( const std::string &bag_path, bool confirm,
                      bool &out_success, std::string &out_message );

/// Check if a service name is an infrastructure service (parameters, lifecycle, etc.)
bool isInfrastructureService( const std::string &service_name );

/// Get the default recorded_by string ($USER@hostname).
std::string getDefaultRecordedBy();

/// Get the machine hostname.
std::string getHostname();

} // namespace hector_recorder

#endif // HECTOR_RECORDER_SERVICE_HANDLERS_H
