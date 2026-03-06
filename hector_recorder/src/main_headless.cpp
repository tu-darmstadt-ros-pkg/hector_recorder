#include "CLI11.hpp"
#include "hector_recorder/arg_parser.hpp"
#include "hector_recorder/recorder_node.hpp"
#include "hector_recorder/utils.h"
#include "rclcpp/rclcpp.hpp"
#include <string>
#include <vector>

using namespace hector_recorder;

int main( int argc, char **argv )
{
  ArgParser arg_parser;
  CustomOptions custom_options;
  rosbag2_storage::StorageOptions storage_options;
  rosbag2_transport::RecordOptions record_options;

  // Default: always publish status in headless mode
  custom_options.publish_status = true;

  bool auto_start = false;

  try {
    arg_parser.parseCommandLineArguments( argc, argv, custom_options, storage_options,
                                          record_options );
  } catch ( const std::exception &e ) {
    RCLCPP_ERROR( rclcpp::get_logger( "hector_recorder.config.cli" ), "Error parsing CLI args: %s",
                  e.what() );
    return 0;
  }

  if ( !custom_options.config_path.empty() ) {
    if ( !hector_recorder::parseYamlConfig( custom_options, record_options, storage_options ) ) {
      return 0;
    }
  }

  // Check if we have enough config to auto-start (topics specified)
  if ( record_options.all_topics || record_options.all_services ||
       !record_options.topics.empty() || !record_options.services.empty() ||
       !record_options.topic_types.empty() || !record_options.regex.empty() ) {
    auto_start = true;
  }

  // Ensure that topics and services start with a slash
  ensureLeadingSlash( record_options.topics );
  ensureLeadingSlash( record_options.services );
  ensureLeadingSlash( record_options.exclude_topics );
  ensureLeadingSlash( record_options.exclude_service_events );

  rclcpp::init( argc, argv );

  auto node = std::make_shared<RecorderNode>( custom_options, storage_options, record_options,
                                              auto_start );

  rclcpp::spin( node );
  rclcpp::shutdown();
  return 0;
}
