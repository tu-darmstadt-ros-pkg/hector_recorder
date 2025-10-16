#include <hector_recorder/arg_parser.hpp>

using namespace hector_recorder;

void ArgParser::parseCommandLineArguments( int argc, char **argv, CustomOptions &custom_options,
                                           rosbag2_storage::StorageOptions &storage_options,
                                           rosbag2_transport::RecordOptions &record_options )
{
  // Find --ros-args in argv
  int cli_argc = argc;
  for ( int i = 1; i < argc; ++i ) {
    if ( std::string( argv[i] ) == "--ros-args" ) {
      cli_argc = i; // Only parse up to --ros-args
      break;
    }
  }

  // Default values for custom options
  custom_options.node_name = "hector_recorder";
  custom_options.config_path = "";
  custom_options.publish_status = false;

  // Tmp values
  std::string output_dir;
  std::string storage_id;
  bool all_flag = false;

  std::vector<std::string> writer_choices = { "sqlite3", "mcap" };
  std::string default_writer = "sqlite3";

  float max_bag_size_gb = 0.0;

  argv = parser.ensure_utf8( argv );

  // Create a group for all manual options
  auto manual_group = parser.add_option_group( "manual", "Manual configuration options" );

  // Add all your options to the group instead of directly to parser
  parser
      .add_option(
          "-o,--output",
          output_dir, "Destination of the bagfile to create, defaults to a timestamped folder in the current directory." )
      ->default_val( "" );

  parser
      .add_option( "-s,--storage", storage_id,
                   "Storage identifier to be used, defaults to '" + default_writer + "'." )
      ->default_val( default_writer )
      ->check( CLI::IsMember( writer_choices ) );

  parser
      .add_option( "-t,--topics", record_options.topics, "Space-delimited list of topics to record." )
      ->expected( 1, -1 )
      ->delimiter( ' ' );

  parser
      .add_option( "--services", record_options.services,
                   "Space-delimited list of services to record." )
      ->expected( 1, -1 )
      ->delimiter( ' ' );

  parser
      .add_option( "--topic-types", record_options.topic_types,
                   "Space-delimited list of topic types to record." )
      ->expected( 1, -1 )
      ->delimiter( ' ' );

  parser
      .add_flag( "-a,--a,--all", all_flag, "Record all topics and services. (Exclude hidden topic)" )
      ->default_val( false );

  parser
      .add_flag( "--all-topics", record_options.all_topics,
                 "Record all topics (Exclude hidden topic)." )
      ->default_val( false );

  parser
      .add_flag( "--all-services", record_options.all_services,
                 "Record all services via service event topics." )
      ->default_val( false );

  parser
      .add_option( "-e,--e,--regex", record_options.regex,
                   "Record only topics and services containing provided regular expression. Note:  "
                   "--all, --all-topics, --all-services or --all-actions will override --regex." )
      ->default_val( "" );

  parser
      .add_option( "--exclude-regex", record_options.exclude_regex,
                   "Exclude topics and services containing provided regular expression. Works on "
                   "top of --all, --all-topics, --all-services, --all-actions, --topics, "
                   "--services, --actions or --regex." )
      ->default_val( "" );

  parser
      .add_option( "--exclude-topic-types", record_options.exclude_topic_types,
                   "Space-delimited list of topic types not being recorded. Works on top of --all, "
                   "--all-topics, --topics or --regex." )
      ->expected( 1, -1 )
      ->delimiter( ' ' )
      ->default_val( "" );

  parser
      .add_option( "--exclude-topics", record_options.exclude_topics,
                   "Space-delimited list of topics not being recorded. Works on top of --all, "
                   "--all-topics, --topics or --regex." )
      ->expected( 1, -1 )
      ->delimiter( ' ' );

  parser
      .add_option( "--exclude-services", record_options.exclude_service_events,
                   "Space-delimited list of services not being recorded. Works on top of --all, "
                   "--all-services, --services or --regex." )
      ->expected( 1, -1 )
      ->delimiter( ' ' );

  // Discovery behavior

  parser
      .add_flag(
          "--include-unpublished-topics", record_options.include_unpublished_topics,
          "Discover and record topics which have no publisher. Subscriptions on such topics will "
          "be made with default QoS unless otherwise specified in a QoS overrides file." )
      ->default_val( false );

  parser
      .add_flag( "--include-hidden-topics", record_options.include_hidden_topics,
                 "Discover and record hidden topics as well. These are topics used internally by "
                 "ROS 2 implementation." )
      ->default_val( false );

  parser
      .add_flag( "--no-discovery", record_options.is_discovery_disabled,
                 "Disables topic auto discovery during recording: only topics present at startup "
                 "will be recorded." )
      ->default_val( false );

  parser
      .add_option( "-p,--p,--polling-interval", record_options.topic_polling_interval,
                   "Time in ms to wait between querying available topics for recording. It has no "
                   "effect if --no-discovery is enabled." )
      ->default_val( 100 );

  parser
      .add_flag( "--publish-status", custom_options.publish_status,
                 "Publish status to /recorder_status topic (default: false)." )
      ->default_val( false );

  parser
      .add_flag( "--ignore-leaf-topics", record_options.ignore_leaf_topics,
                 "Ignore topics without a subscription." )
      ->default_val( false );

  // parser.add_option("--qos-profile-overrides-path", record_options.topic_qos_profile_overrides_path, "Path to a yaml file defining overrides of the QoS profile for specific topics.")
  //     ->default_val("");  // TODO

  // Core Config

  parser
      .add_option( "-f,--f,--serialization-format", record_options.rmw_serialization_format,
                   "The rmw serialization format in which the messages are saved." )
      ->default_val( rmw_get_serialization_format() );
  //->check(CLI::IsMember(serialization_choices));

  auto max_size_opt = parser
                          .add_option( "-b,--b,--max-bag-size", storage_options.max_bagfile_size,
                                       "Maximum size in bytes before the bagfile will be split. "
                                       "Default: %(default)d, recording written in single "
                                       "bagfile and splitting is disabled." )
                          ->default_val( 0 );

  auto max_size_gb_opt =
      parser
          .add_option(
              "--gb,--max-bag-size-gb", max_bag_size_gb,
              "Maximum size in gigabytes before the bagfile will be split. Default: 0 (disabled)." )
          ->default_val( 0.0 );

  max_size_opt->excludes( max_size_gb_opt );
  max_size_gb_opt->excludes( max_size_opt );

  parser
      .add_option( "-d,--d,--max-bag-duration", storage_options.max_bagfile_duration,
                   "Maximum duration in seconds before the bagfile will be split. "
                   "Default: %(default)d, recording written in single bagfile and splitting is "
                   "disabled. If both splitting by size and duration are enabled, the bag will "
                   "split at whichever threshold is reached first." )
      ->default_val( 0 );

  parser
      .add_option( "--max-cache-size", storage_options.max_cache_size,
                   "Maximum size (in bytes) of messages to hold in each buffer of cache. "
                   "Default: %(default)d. The cache is handled through double buffering, which "
                   "means that in pessimistic case up to twice the parameter value of memory is "
                   "needed. A rule of thumb is to cache an order of magnitude corresponding to "
                   "about one second of total recorded data volume. "
                   "If the value specified is 0, then every message is directly written to disk." )
      ->default_val( 100 * 1024 * 1024 );

  parser
      .add_flag( "--disable-keyboard-controls", record_options.disable_keyboard_controls,
                 "Disables keyboard controls for recorder." )
      ->default_val( false );

  parser
      .add_flag( "--start-paused", record_options.start_paused,
                 "Start the recorder in a paused state." )
      ->default_val( false );

  parser
      .add_flag( "--use-sim-time", record_options.use_sim_time,
                 "Use simulation time for message timestamps by subscribing to the /clock topic. "
                 "Until first /clock message is received, no messages will be written to bag." )
      ->default_val( false );

  parser
      .add_option( "--node-name", custom_options.node_name,
                   "Specify the recorder node name. Default is hector_recorder." )
      ->default_val( "hector_recorder" );

  parser
      .add_option( "--custom-data", storage_options.custom_data,
                   "Space-delimited list of key=value pairs. Store the custom data in metadata "
                   "under the 'rosbag2_bagfile_information/custom_data'. The key=value pair can "
                   "appear more than once. The last value will override the former ones." )
      ->expected( 1, -1 )
      ->delimiter( ' ' );

  parser
      .add_flag( "--snapshot-mode", storage_options.snapshot_mode,
                 "Enable snapshot mode. Messages will not be written to the bagfile until the "
                 "'/rosbag2_recorder/snapshot' service is called. e.g. \n ros2 service call "
                 "/rosbag2_recorder/snapshot rosbag2_interfaces/Snapshot" )
      ->default_val( false );

  parser
      .add_option( "--compression-queue-size", record_options.compression_queue_size,
                   "Number of files or messages that may be queued for compression before being "
                   "dropped. Default is %(default)d." )
      ->default_val( 1 );

  parser
      .add_option( "--compression-threads", record_options.compression_threads,
                   "Number of files or messages that may be compressed in parallel. Default is "
                   "%(default)d, which will be interpreted as the number of CPU cores." )
      ->default_val( 0 );

  parser
      .add_option(
          "--compression-threads-priority", record_options.compression_threads_priority,
          "Compression threads scheduling priority. \nFor Windows the valid values are:"
          " THREAD_PRIORITY_LOWEST=-2, THREAD_PRIORITY_BELOW_NORMAL=-1 and"
          " THREAD_PRIORITY_NORMAL=0. Please refer to"
          " https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/"
          "nf-processthreadsapi-setthreadpriority"
          " for details.\n"
          "For POSIX compatible OSes this is the 'nice' value. The nice value range is"
          " -20 to +19 where -20 is highest, 0 default and +19 is lowest."
          " Please refer to https://man7.org/linux/man-pages/man2/nice.2.html for details.\n"
          "Default is %(default)d." )
      ->default_val( 0 );

  parser
      .add_option( "--compression-mode", record_options.compression_mode,
                   "Choose mode of compression for the storage. Default: %(default)s." )
      ->default_val( "none" )
      ->check( CLI::IsMember( { "none", "file", "message" } ) );

  parser
      .add_option( "--compression-format", record_options.compression_format,
                   "Choose the compression format/algorithm. Has no effect if no compression mode "
                   "is chosen. Default: %(default)s." )
      ->default_val( "" );
  //->check(CLI::IsMember(get_registered_compressors()));

  parser
      .add_option( "--publish-status-topic", custom_options.status_topic,
                   "The topic to publish the recorder status on. Default: %(default)s." )
      ->default_val( "recorder_status" );

  auto config_opt =
      parser
          .add_option( "-c,--c,--config", custom_options.config_path,
                       "Path to a YAML configuration file. Mutually exclusive with other options." )
          ->default_val( "" )
          ->check( CLI::ExistingFile );

  // Make config mutually exclusive with every other option except itself
  for ( auto &opt : parser.get_options() ) {
    if ( opt != config_opt ) {
      config_opt->excludes( opt );
    }
  }

  try {
    // Use only the arguments before --ros-args for CLI11
    parser.parse( cli_argc, argv );
  } catch ( const CLI::ParseError &e ) {
    std::exit( parser.exit( e ) );
  }

  std::string final_output_dir;
  final_output_dir = hector_recorder::resolveOutputDirectory( output_dir );
  // custom_options.resolved_output_dir = final_output_dir;
  storage_options.uri = final_output_dir;

  if ( all_flag ) {
    record_options.all_topics = true;
    record_options.all_services = true;
  }

  // logic to handle max_bag_size_gb
  if ( max_bag_size_gb > 0.0 ) {
    uint64_t max_bag_size_bytes_from_gb =
        static_cast<uint64_t>( max_bag_size_gb * 1024 * 1024 * 1024 );
    storage_options.max_bagfile_size =
        max_bag_size_bytes_from_gb; // Use the value from --max-bag-size-gb
  }
}