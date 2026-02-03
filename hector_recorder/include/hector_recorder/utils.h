#pragma once

#include "rosbag2_transport/recorder.hpp"

#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fmt/chrono.h>
#include <fmt/core.h>
#include <limits.h>
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
struct CustomOptions {
  std::string node_name;
  std::string config_path;
  std::string qos_profile_overrides_path;
  std::string status_topic = "recorder_status";
  bool publish_status;
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
std::string clipString( const std::string &str, int max_length );
void ensureLeadingSlash( std::vector<std::string> &vector );
static std::string expandUserAndEnv( std::string s );
std::string resolveOutputUriToAbsolute( std::string &uri );
} // namespace hector_recorder