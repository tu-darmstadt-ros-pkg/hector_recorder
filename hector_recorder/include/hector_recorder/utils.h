#ifndef HECTOR_RECORDER_UTILS_H
#define HECTOR_RECORDER_UTILS_H

#include "rosbag2_transport/recorder.hpp"

#include "hector_recorder/throttle_config.hpp"

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

std::string formatMemory( uint64_t bytes );
std::string rateToString( double rate );
std::string bandwidthToString( double bandwidth );
int calculateRequiredLines( const std::vector<std::string> &lines );

std::string clipString( const std::string &str, int max_length );
void ensureLeadingSlash( std::vector<std::string> &vector );
static std::string expandUserAndEnv( std::string s );
std::string resolveOutputUriToAbsolute( const std::string &uri );

} // namespace hector_recorder

#endif // HECTOR_RECORDER_UTILS_H