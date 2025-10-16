#include "CLI11.hpp"
#include "hector_recorder/arg_parser.hpp"
#include "hector_recorder/terminal_ui.hpp"
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
      return 0; // Exit if config parsing fails
    };
  }

  if ( !record_options.all_topics && !record_options.all_services &&
       record_options.topics.empty() && record_options.services.empty() &&
       record_options.topic_types.empty() && record_options.regex.empty() ) {
    RCLCPP_ERROR( rclcpp::get_logger( "hector_recorder.config" ),
                  "Need to specify at least one option out of --all, --all-topics, --all-services, "
                  "--services, --topics, --topic-types, --regex or specify them in --config" );
    return 0; // Exit if no valid recording options are provided
  }

  // Ensure that topics and services start with a slash
  ensureLeadingSlash( record_options.topics );
  ensureLeadingSlash( record_options.services );
  ensureLeadingSlash( record_options.exclude_topics );
  ensureLeadingSlash( record_options.exclude_service_events );

  // Add ROS-args: Disable stdout ros logs to prevent interference with terminal UI
  std::vector<std::string> argv_storage( argv, argv + argc );
  argv_storage.push_back( "--ros-args" );
  argv_storage.push_back( "--disable-stdout-logs" );

  std::vector<char *> new_argv;
  new_argv.reserve( argv_storage.size() );
  for ( auto &s : argv_storage ) new_argv.push_back( s.data() );

  int new_argc = static_cast<int>( new_argv.size() );
  rclcpp::init( new_argc, new_argv.data() );

  auto ui_node = std::make_shared<TerminalUI>( custom_options, storage_options, record_options );

  rclcpp::spin( ui_node );
  rclcpp::shutdown();
  return 0;
}
