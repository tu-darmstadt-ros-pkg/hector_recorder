#include "hector_recorder/service_handlers.h"
#include "hector_recorder/config_yaml.h"
#include "hector_recorder/modified/recorder_impl.hpp"
#include "rosbag2_cpp/writer.hpp"
#include "rosbag2_cpp/writers/sequential_writer.hpp"
#include "rosbag2_storage/metadata_io.hpp"
#include <filesystem>
#include <fstream>

namespace hector_recorder
{

// ========================================================================
// Shared service handler implementations
// ========================================================================

void fillRecorderStatus( hector_recorder_msgs::msg::RecorderStatus &status_msg,
                         RecorderImpl *recorder, const CustomOptions &custom_options,
                         const rosbag2_storage::StorageOptions &storage_options,
                         rclcpp::Node *node )
{
  status_msg.node_name = node->get_fully_qualified_name();
  status_msg.output_dir = storage_options.uri;

  // Determine state
  if ( recorder && recorder->is_recording() ) {
    if ( recorder->is_paused() ) {
      status_msg.state = hector_recorder_msgs::msg::RecorderStatus::PAUSED;
    } else {
      status_msg.state = hector_recorder_msgs::msg::RecorderStatus::RECORDING;
    }
  } else {
    status_msg.state = hector_recorder_msgs::msg::RecorderStatus::IDLE;
  }

  if ( recorder ) {
    status_msg.files = recorder->get_files();
    status_msg.duration = recorder->get_bagfile_duration();
    status_msg.size = recorder->get_bagfile_size();

    for ( const auto &topic_info : recorder->get_topics_info() ) {
      hector_recorder_msgs::msg::TopicInfo topic_msg;
      topic_msg.topic = topic_info.first;
      topic_msg.msg_count = topic_info.second.message_count();
      topic_msg.frequency = topic_info.second.mean_frequency();
      topic_msg.bandwidth = topic_info.second.bandwidth();
      topic_msg.size = topic_info.second.size();
      topic_msg.type = topic_info.second.topic_type();
      topic_msg.publisher_count = topic_info.second.publisher_count();
      topic_msg.qos_reliability = topic_info.second.qos_reliability();
      topic_msg.throttled = custom_options.topic_throttle.count( topic_info.first ) > 0;
      status_msg.topics.push_back( topic_msg );
    }
  }
}

void handleGetConfig( const CustomOptions &custom_options,
                      const rosbag2_transport::RecordOptions &record_options,
                      const rosbag2_storage::StorageOptions &storage_options,
                      const std::string &raw_output_uri, std::string &out_config_yaml )
{
  out_config_yaml =
      serializeConfigToYaml( custom_options, record_options, storage_options, raw_output_uri );
}

void handleGetRecorderInfo( const CustomOptions &custom_options, std::string &out_hostname,
                            std::string &out_recorded_by, std::string &out_config_path )
{
  out_hostname = getHostname();
  out_recorded_by =
      custom_options.recorded_by.empty() ? getDefaultRecordedBy() : custom_options.recorded_by;
  out_config_path = custom_options.config_path;
}

static void createAndStartRecorder( std::unique_ptr<RecorderImpl> &recorder,
                                    const rosbag2_storage::StorageOptions &storage_options,
                                    const rosbag2_transport::RecordOptions &record_options,
                                    const CustomOptions &custom_options, rclcpp::Node *node )
{
  auto writer_impl = std::make_unique<rosbag2_cpp::writers::SequentialWriter>();
  auto writer = std::make_shared<rosbag2_cpp::Writer>( std::move( writer_impl ) );
  recorder = std::make_unique<RecorderImpl>( node, writer, storage_options, record_options,
                                             custom_options.topic_throttle );
  recorder->record();
}

void handleStartRecording( std::unique_ptr<RecorderImpl> &recorder,
                           rosbag2_storage::StorageOptions &storage_options,
                           const rosbag2_transport::RecordOptions &record_options,
                           const CustomOptions &custom_options,
                           const std::string &raw_output_uri,
                           const std::string &request_output_dir,
                           const std::string &request_recorded_by, rclcpp::Node *node,
                           bool &out_success, std::string &out_message,
                           std::string &out_bag_path )
{
  if ( recorder && recorder->is_recording() ) {
    out_success = false;
    out_message = "Already recording. Stop first.";
    return;
  }

  try {
    if ( !request_output_dir.empty() ) {
      storage_options.uri = resolveOutputDirectory( request_output_dir );
    } else {
      storage_options.uri = resolveOutputDirectory( raw_output_uri );
    }

    // Store recorded_by in bag custom_data so it persists in metadata.yaml
    // Priority: request > custom_options > default ($USER@hostname)
    std::string recorded_by = !request_recorded_by.empty() ? request_recorded_by
                              : !custom_options.recorded_by.empty() ? custom_options.recorded_by
                                                                    : getDefaultRecordedBy();
    storage_options.custom_data["recorded_by"] = recorded_by;

    createAndStartRecorder( recorder, storage_options, record_options, custom_options, node );
    out_success = true;
    out_message = "Recording started.";
    out_bag_path = storage_options.uri;
    RCLCPP_INFO( node->get_logger(), "Recording started: %s", storage_options.uri.c_str() );
  } catch ( const std::exception &e ) {
    out_success = false;
    out_message = std::string( "Failed to start recording: " ) + e.what();
    RCLCPP_ERROR( node->get_logger(), "%s", out_message.c_str() );
  }
}

void handleStopRecording( std::unique_ptr<RecorderImpl> &recorder,
                          const rosbag2_storage::StorageOptions &storage_options,
                          bool &out_success, std::string &out_message,
                          std::string &out_bag_path )
{
  if ( !recorder || !recorder->is_recording() ) {
    out_success = false;
    out_message = "Not currently recording.";
    return;
  }

  try {
    out_bag_path = storage_options.uri;
    recorder->stop();
    recorder.reset();
    out_success = true;
    out_message = "Recording stopped.";
  } catch ( const std::exception &e ) {
    out_success = false;
    out_message = std::string( "Failed to stop recording: " ) + e.what();
  }
}

void handleApplyConfig( std::unique_ptr<RecorderImpl> &recorder, CustomOptions &custom_options,
                        rosbag2_transport::RecordOptions &record_options,
                        rosbag2_storage::StorageOptions &storage_options,
                        std::string &raw_output_uri, const std::string &config_yaml,
                        bool restart, rclcpp::Node *node, bool &out_success,
                        std::string &out_message, std::string &out_active_config_yaml )
{
  try {
    CustomOptions new_custom = custom_options;
    rosbag2_transport::RecordOptions new_record = record_options;
    rosbag2_storage::StorageOptions new_storage = storage_options;

    if ( !parseYamlConfigFromString( config_yaml, new_custom, new_record, new_storage ) ) {
      out_success = false;
      out_message = "Failed to parse YAML config.";
      return;
    }

    bool was_recording = recorder && recorder->is_recording();

    if ( restart && was_recording ) {
      recorder->stop();
      recorder.reset();
    }

    custom_options = new_custom;
    record_options = new_record;
    raw_output_uri = new_storage.uri;
    storage_options = new_storage;

    if ( restart && was_recording ) {
      // Full restart: stop current recording, start fresh bag
      storage_options.uri = resolveOutputDirectory( raw_output_uri );
      createAndStartRecorder( recorder, storage_options, record_options, custom_options, node );
      RCLCPP_INFO( node->get_logger(), "Config applied and recording restarted." );
    } else if ( was_recording ) {
      // Hot update: update topic filter, throttle configs, and restart discovery
      recorder->update_record_options( record_options );
      recorder->update_throttle_configs( custom_options.topic_throttle );
      RCLCPP_INFO( node->get_logger(), "Config applied, new topics will be added to current bag." );
    }

    out_success = true;
    if ( restart && was_recording ) {
      out_message = "Config applied, recording restarted.";
    } else if ( was_recording ) {
      out_message = "Config applied, new topics will be added to current recording.";
    } else {
      out_message = "Config applied.";
    }
    out_active_config_yaml =
        serializeConfigToYaml( custom_options, record_options, storage_options, raw_output_uri );
  } catch ( const std::exception &e ) {
    out_success = false;
    out_message = std::string( "Failed to apply config: " ) + e.what();
  }
}

void handleSaveConfig( const std::string &config_yaml, const std::string &file_path,
                       bool &out_success, std::string &out_message )
{
  try {
    std::filesystem::path path( file_path );
    if ( path.has_parent_path() ) {
      std::filesystem::create_directories( path.parent_path() );
    }

    std::ofstream ofs( file_path );
    if ( !ofs.is_open() ) {
      out_success = false;
      out_message = "Failed to open file for writing: " + file_path;
      return;
    }

    ofs << config_yaml;
    ofs.close();

    out_success = true;
    out_message = "Config saved to " + file_path;
  } catch ( const std::exception &e ) {
    out_success = false;
    out_message = std::string( "Failed to save config: " ) + e.what();
  }
}

void handleGetAvailableTopics( rclcpp::Node *node, std::vector<std::string> &out_topics,
                               std::vector<std::string> &out_types )
{
  auto all_topics = node->get_topic_names_and_types();
  for ( const auto &[name, types] : all_topics ) {
    out_topics.push_back( name );
    std::string type_str;
    for ( size_t i = 0; i < types.size(); ++i ) {
      if ( i > 0 )
        type_str += ", ";
      type_str += types[i];
    }
    out_types.push_back( type_str );
  }
}

bool isInfrastructureService( const std::string &service_name )
{
  auto pos = service_name.rfind( '/' );
  if ( pos == std::string::npos )
    return false;
  std::string_view leaf( service_name.data() + pos + 1, service_name.size() - pos - 1 );

  // Parameter services
  if ( leaf == "list_parameters" || leaf == "describe_parameters" ||
       leaf == "get_parameters" || leaf == "set_parameters" ||
       leaf == "get_parameter_types" || leaf == "set_parameters_atomically" )
    return true;

  // Lifecycle services
  if ( leaf == "change_state" || leaf == "get_state" ||
       leaf == "get_available_states" || leaf == "get_available_transitions" ||
       leaf == "get_transition_graph" )
    return true;

  // Type description service
  if ( leaf == "get_type_description" )
    return true;

  // Logger services
  if ( leaf == "set_logger_levels" || leaf == "get_logger_levels" )
    return true;

  return false;
}

void handleGetAvailableServices( rclcpp::Node *node, std::vector<std::string> &out_services,
                                 std::vector<std::string> &out_types )
{
  auto all_services = node->get_service_names_and_types();
  for ( const auto &[name, types] : all_services ) {
    if ( isInfrastructureService( name ) )
      continue;
    out_services.push_back( name );
    std::string type_str;
    for ( size_t i = 0; i < types.size(); ++i ) {
      if ( i > 0 )
        type_str += ", ";
      type_str += types[i];
    }
    out_types.push_back( type_str );
  }
}

std::string getHostname()
{
  char hostname[256];
  if ( gethostname( hostname, sizeof( hostname ) ) == 0 ) {
    return std::string( hostname );
  }
  return "unknown";
}

std::string getDefaultRecordedBy()
{
  std::string user;
  const char *env_user = std::getenv( "USER" );
  if ( env_user ) {
    user = env_user;
  } else {
    user = "unknown";
  }
  return user + "@" + getHostname();
}

// ========================================================================
// Bag browsing service handlers
// ========================================================================

/// Compute total size of all files in a directory (non-recursive into subdirs of bags)
static uint64_t directorySize( const fs::path &dir )
{
  uint64_t total = 0;
  std::error_code ec;
  for ( const auto &entry : fs::recursive_directory_iterator( dir, ec ) ) {
    if ( entry.is_regular_file( ec ) ) {
      total += entry.file_size( ec );
    }
  }
  return total;
}

/// Read a BagInfo from a bag directory using its metadata.yaml
static bool readBagInfo( const fs::path &bag_dir, hector_recorder_msgs::msg::BagInfo &info )
{
  rosbag2_storage::MetadataIo metadata_io;
  if ( !metadata_io.metadata_file_exists( bag_dir.string() ) ) {
    return false;
  }

  try {
    auto metadata = metadata_io.read_metadata( bag_dir.string() );

    info.name = bag_dir.filename().string();
    info.path = bag_dir.string();
    info.size_bytes = directorySize( bag_dir );
    info.storage_id = metadata.storage_identifier;
    info.topic_count = static_cast<uint32_t>( metadata.topics_with_message_count.size() );
    info.message_count = static_cast<uint32_t>( metadata.message_count );
    info.duration_secs =
        std::chrono::duration<double>( metadata.duration ).count();

    // Format start time as ISO 8601
    auto start_ns = metadata.starting_time.time_since_epoch();
    auto start_sec = std::chrono::duration_cast<std::chrono::seconds>( start_ns );
    std::time_t start_time_t = start_sec.count();
    std::tm lt{};
    localtime_r( &start_time_t, &lt );
    char buf[64];
    std::strftime( buf, sizeof( buf ), "%Y-%m-%dT%H:%M:%S", &lt );
    info.start_time = std::string( buf );

    // Read recorded_by from custom_data if available
    auto it = metadata.custom_data.find( "recorded_by" );
    if ( it != metadata.custom_data.end() ) {
      info.recorded_by = it->second;
    }

    return true;
  } catch ( const std::exception & ) {
    return false;
  }
}

void handleListBags( const std::string &path,
                     const rosbag2_storage::StorageOptions &storage_options,
                     std::vector<hector_recorder_msgs::msg::BagInfo> &out_bags,
                     bool &out_success, std::string &out_message )
{
  std::string scan_dir = path.empty() ? storage_options.uri : path;

  // Resolve ~ and env vars
  scan_dir = resolveOutputUriToAbsolute( scan_dir );

  // If the path itself is a bag, go up to its parent
  rosbag2_storage::MetadataIo metadata_io;
  if ( metadata_io.metadata_file_exists( scan_dir ) ) {
    scan_dir = fs::path( scan_dir ).parent_path().string();
  }

  if ( !fs::is_directory( scan_dir ) ) {
    out_success = false;
    out_message = "Path is not a directory: " + scan_dir;
    return;
  }

  std::error_code ec;
  for ( const auto &entry : fs::directory_iterator( scan_dir, ec ) ) {
    if ( !entry.is_directory( ec ) )
      continue;

    hector_recorder_msgs::msg::BagInfo info;
    if ( readBagInfo( entry.path(), info ) ) {
      out_bags.push_back( std::move( info ) );
    }
  }

  // Sort by start_time descending (newest first)
  std::sort( out_bags.begin(), out_bags.end(),
             []( const auto &a, const auto &b ) { return a.start_time > b.start_time; } );

  out_success = true;
  out_message = "Found " + std::to_string( out_bags.size() ) + " bags in " + scan_dir;
}

void handleGetBagDetails( const std::string &bag_path,
                          hector_recorder_msgs::msg::BagInfo &out_info,
                          std::vector<hector_recorder_msgs::msg::BagTopicInfo> &out_topics,
                          bool &out_success, std::string &out_message )
{
  if ( !readBagInfo( bag_path, out_info ) ) {
    out_success = false;
    out_message = "Failed to read bag metadata from: " + bag_path;
    return;
  }

  // Read per-topic details
  try {
    rosbag2_storage::MetadataIo metadata_io;
    auto metadata = metadata_io.read_metadata( bag_path );

    for ( const auto &topic_info : metadata.topics_with_message_count ) {
      hector_recorder_msgs::msg::BagTopicInfo ti;
      ti.name = topic_info.topic_metadata.name;
      ti.type = topic_info.topic_metadata.type;
      ti.message_count = topic_info.message_count;
      ti.serialization_format = topic_info.topic_metadata.serialization_format;
      out_topics.push_back( std::move( ti ) );
    }

    out_success = true;
    out_message = "OK";
  } catch ( const std::exception &e ) {
    out_success = false;
    out_message = std::string( "Failed to read bag details: " ) + e.what();
  }
}

void handleDeleteBag( const std::string &bag_path, bool confirm,
                      bool &out_success, std::string &out_message )
{
  if ( !confirm ) {
    out_success = false;
    out_message = "Delete not confirmed. Set confirm=true to actually delete.";
    return;
  }

  if ( !fs::is_directory( bag_path ) ) {
    out_success = false;
    out_message = "Not a directory: " + bag_path;
    return;
  }

  // Safety: only delete if it contains a metadata.yaml (i.e., it's a rosbag)
  rosbag2_storage::MetadataIo metadata_io;
  if ( !metadata_io.metadata_file_exists( bag_path ) ) {
    out_success = false;
    out_message = "Not a valid rosbag directory (no metadata.yaml): " + bag_path;
    return;
  }

  try {
    std::error_code ec;
    auto removed = fs::remove_all( bag_path, ec );
    if ( ec ) {
      out_success = false;
      out_message = "Failed to delete: " + ec.message();
    } else {
      out_success = true;
      out_message = "Deleted " + bag_path + " (" + std::to_string( removed ) + " files removed)";
    }
  } catch ( const std::exception &e ) {
    out_success = false;
    out_message = std::string( "Failed to delete bag: " ) + e.what();
  }
}

} // namespace hector_recorder
