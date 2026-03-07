#ifndef HECTOR_RECORDER_UTILS_H
#define HECTOR_RECORDER_UTILS_H

#include "rosbag2_transport/recorder.hpp"

#include "hector_recorder/throttle_config.hpp"
#include "hector_recorder_msgs/msg/bag_info.hpp"
#include "hector_recorder_msgs/msg/bag_topic_info.hpp"
#include "hector_recorder_msgs/msg/recorder_status.hpp"
#include "hector_recorder_msgs/msg/topic_info.hpp"

#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fmt/chrono.h>
#include <fmt/core.h>
#include <climits>
#include <rclcpp/qos.hpp>
#include <regex>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>

namespace fs = std::filesystem;

namespace hector_recorder
{
class RecorderImpl;

struct CustomOptions {
  std::string node_name;
  std::string config_path;
  std::string qos_profile_overrides_path;
  std::string status_topic = "recorder_status";
  bool publish_status;
  ThrottleConfigMap topic_throttle;
  std::string recorded_by; // e.g. "alice@robot-pc", defaults to $USER@hostname
};

std::string getAbsolutePath( const std::string &path );
static std::string make_timestamped_folder_name();
static bool is_rosbag_dir( const fs::path &dir );
static fs::path find_rosbag_ancestor( const fs::path &dir );
std::string resolveOutputDirectory( const std::string &output_dir );

std::unordered_map<std::string, rclcpp::QoS> convert_yaml_to_qos_overrides( const YAML::Node &root );
std::unordered_map<std::string, rclcpp::QoS> load_qos_overrides_from_file( const std::string &path );

std::string formatMemory( uint64_t bytes );
std::string rateToString( double rate );
std::string bandwidthToString( double bandwidth );
int calculateRequiredLines( const std::vector<std::string> &lines );

bool parseYamlConfig( CustomOptions &custom_options, rosbag2_transport::RecordOptions &record_options,
                      rosbag2_storage::StorageOptions &storage_options );
bool parseYamlNode( const YAML::Node &config, CustomOptions &custom_options,
                    rosbag2_transport::RecordOptions &record_options,
                    rosbag2_storage::StorageOptions &storage_options );
bool parseYamlConfigFromString( const std::string &yaml_string, CustomOptions &custom_options,
                                rosbag2_transport::RecordOptions &record_options,
                                rosbag2_storage::StorageOptions &storage_options );
std::string serializeConfigToYaml( const CustomOptions &custom_options,
                                   const rosbag2_transport::RecordOptions &record_options,
                                   const rosbag2_storage::StorageOptions &storage_options,
                                   const std::string &output_override = "" );
std::string clipString( const std::string &str, int max_length );
void ensureLeadingSlash( std::vector<std::string> &vector );
static std::string expandUserAndEnv( std::string s );
std::string resolveOutputUriToAbsolute( const std::string &uri );

// ========================================================================
// Shared service handler helpers (used by both RecorderNode and TerminalUI)
// ========================================================================

/// Populate a RecorderStatus message from the current recorder state.
/// Only includes live data that changes every tick. Static/rarely-changing
/// data (config, hostname, available topics) is served via on-demand services.
void fillRecorderStatus( hector_recorder_msgs::msg::RecorderStatus &status_msg,
                         RecorderImpl *recorder, const CustomOptions &custom_options,
                         const rosbag2_storage::StorageOptions &storage_options,
                         rclcpp::Node *node );

/// Handle StartRecording service: resolve output, create recorder, start.
/// On success sets recorder and updates storage_options.uri.
void handleStartRecording( std::unique_ptr<RecorderImpl> &recorder,
                           rosbag2_storage::StorageOptions &storage_options,
                           const rosbag2_transport::RecordOptions &record_options,
                           const CustomOptions &custom_options,
                           const std::string &raw_output_uri,
                           const std::string &request_output_dir, rclcpp::Node *node,
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

/// Get the default recorded_by string ($USER@hostname).
std::string getDefaultRecordedBy();

/// Get the machine hostname.
std::string getHostname();

} // namespace hector_recorder

#endif // HECTOR_RECORDER_UTILS_H