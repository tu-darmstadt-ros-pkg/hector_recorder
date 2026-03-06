#include "hector_recorder/utils.h"
#include "hector_recorder/modified/recorder_impl.hpp"
#include "rosbag2_cpp/writer.hpp"
#include "rosbag2_cpp/writers/sequential_writer.hpp"
#include <filesystem>
#include <fstream>

namespace hector_recorder
{
std::string getAbsolutePath( const std::string &path )
{
  try {
    return std::filesystem::canonical( path );
  } catch ( const std::filesystem::filesystem_error &e ) {
    throw std::runtime_error( "Error resolving absolute path for '" + path + "': " + e.what() );
  }
}

static std::string make_timestamped_folder_name()
{
  auto now = std::chrono::system_clock::now();
  std::time_t t = std::chrono::system_clock::to_time_t( now );
  std::tm lt{};
#if defined( _WIN32 )
  localtime_s( &lt, &t );
#else
  localtime_r( &t, &lt );
#endif
  std::ostringstream oss;
  oss << "rosbag2_" << std::put_time( &lt, "%Y_%m_%d-%H_%M_%S" );
  return oss.str();
}

static bool is_rosbag_dir( const fs::path &dir )
{
  const fs::path meta = dir / "metadata.yaml";
  return fs::exists( meta ) && fs::is_regular_file( meta );
}

static fs::path find_rosbag_ancestor( const fs::path &dir )
{
  if ( dir.empty() )
    return {};

  fs::path p = dir;
  while ( true ) {
    if ( fs::exists( p ) && fs::is_directory( p ) && is_rosbag_dir( p ) ) {
      return p;
    }
    fs::path parent = p.parent_path();

    // Important: If parent is the same as p, we are at the root directory
    if ( parent == p || parent.empty() ) {
      break;
    }
    p = parent;
  }
  return {};
}

std::string resolveOutputDirectory( const std::string &output_dir )
{
  const fs::path cwd = fs::current_path();
  const std::string ts = make_timestamped_folder_name();
  const bool had_trailing_sep = !output_dir.empty() && ( output_dir.back() == '/' );

  // Expand ~ and $ENV before any path operations
  const std::string expanded = expandUserAndEnv( output_dir );

  fs::path target; // ← This directory will be created by rosbag2

  if ( expanded.empty() ) {
    // No output_dir → CWD/rosbag2_<timestamp>
    target = cwd / ts;
  } else {
    fs::path p = fs::path( expanded ).lexically_normal();
    const bool exists = fs::exists( p );

    if ( exists ) {
      if ( !fs::is_directory( p ) ) {
        throw std::runtime_error( "Specified output path exists but is not a directory: " +
                                  p.string() );
      }
      if ( is_rosbag_dir( p ) ) {
        // Existing rosbag dir → create timestamped sibling in parent
        target = p.parent_path() / ts;
      } else {
        // Existing directory → timestamped rosbag subdirectory
        target = p / ts;
      }
    } else {
      fs::path par = p.parent_path();
      if ( par.empty() ) {
        // Only one name → Bag under CWD/<name>
        target = cwd / p;
      } else {
        if ( fs::exists( par ) && !fs::is_directory( par ) ) {
          throw std::runtime_error( "Specified output parent exists but is not a directory: " +
                                    par.string() );
        }
        // Trailing Slash signals Container-Semantic → timestamped directory
        // Else: Just use the name as bag directory
        target = had_trailing_sep ? ( p / ts ) : p;
      }
    }
  }

  const fs::path container = target.parent_path();

  // Impede placing a new rosbag inside an existing rosbag directory
  if ( !container.empty() ) {
    if ( fs::path bad = find_rosbag_ancestor( container ); !bad.empty() ) {
      throw std::runtime_error( "Cannot place a new rosbag inside an existing rosbag directory: " +
                                bad.string() );
    }
  }

  // Target directory must not exist yet
  if ( fs::exists( target ) ) {
    throw std::runtime_error( "Target directory already exists: " + target.string() );
  }

  // Create the parent directory if it does not exist
  try {
    if ( !container.empty() && !fs::exists( container ) ) {
      fs::create_directories( container );
    }
  } catch ( const fs::filesystem_error &e ) {
    throw std::runtime_error( "Failed to create parent directories for '" + container.string() +
                              "': " + e.what() );
  }

  return target.string();
}

static rmw_time_t parse_duration( const YAML::Node &time_dict, const std::string &key_name )
{
  if ( !time_dict || !time_dict.IsMap() ) {
    throw std::runtime_error( "Key '" + key_name + "' must be a map with fields {sec, nsec}." );
  }
  if ( !time_dict["sec"] || !time_dict["nsec"] ) {
    throw std::runtime_error( "Key '" + key_name + "' must include both 'sec' and 'nsec'." );
  }

  const int64_t sec = time_dict["sec"].as<int64_t>();
  const int64_t nsec = time_dict["nsec"].as<int64_t>();

  if ( sec < 0 || ( sec == 0 && nsec < 0 ) ) {
    throw std::runtime_error( "Time duration may not be a negative value for key '" + key_name +
                              "'." );
  }

  rmw_time_t t{};
  t.sec = static_cast<int32_t>( sec );
  t.nsec = static_cast<uint32_t>( nsec );
  return t;
}

static rmw_qos_history_policy_t parse_history( const std::string &s )
{
  if ( s == "keep_last" )
    return RMW_QOS_POLICY_HISTORY_KEEP_LAST;
  if ( s == "keep_all" )
    return RMW_QOS_POLICY_HISTORY_KEEP_ALL;
  if ( s == "system_default" )
    return RMW_QOS_POLICY_HISTORY_SYSTEM_DEFAULT;
  throw std::runtime_error( "Invalid history policy: '" + s + "'" );
}

static rmw_qos_reliability_policy_t parse_reliability( const std::string &s )
{
  if ( s == "reliable" )
    return RMW_QOS_POLICY_RELIABILITY_RELIABLE;
  if ( s == "best_effort" )
    return RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
  if ( s == "system_default" )
    return RMW_QOS_POLICY_RELIABILITY_SYSTEM_DEFAULT;
  throw std::runtime_error( "Invalid reliability policy: '" + s + "'" );
}

static rmw_qos_durability_policy_t parse_durability( const std::string &s )
{
  if ( s == "volatile" )
    return RMW_QOS_POLICY_DURABILITY_VOLATILE;
  if ( s == "transient_local" )
    return RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL;
  if ( s == "system_default" )
    return RMW_QOS_POLICY_DURABILITY_SYSTEM_DEFAULT;
  throw std::runtime_error( "Invalid durability policy: '" + s + "'" );
}

static rmw_qos_liveliness_policy_t parse_liveliness( const std::string &s )
{
  if ( s == "automatic" )
    return RMW_QOS_POLICY_LIVELINESS_AUTOMATIC;
  if ( s == "manual_by_topic" )
    return RMW_QOS_POLICY_LIVELINESS_MANUAL_BY_TOPIC;
  if ( s == "system_default" )
    return RMW_QOS_POLICY_LIVELINESS_SYSTEM_DEFAULT;
  throw std::runtime_error( "Invalid liveliness policy: '" + s + "'" );
}

static rclcpp::QoS interpret_node_as_qos( const YAML::Node &profile_node )
{
  if ( !profile_node || !profile_node.IsMap() ) {
    throw std::runtime_error( "QoS profile must be a map (topic -> {policies...})." );
  }

  rmw_qos_profile_t rmw = rmw_qos_profile_default;

  for ( const auto &kv : profile_node ) {
    const std::string key = kv.first.as<std::string>();
    const YAML::Node &val = kv.second;

    if ( key == "deadline" ) {
      rmw.deadline = parse_duration( val, key );
      continue;
    }
    if ( key == "lifespan" ) {
      rmw.lifespan = parse_duration( val, key );
      continue;
    }
    if ( key == "liveliness_lease_duration" ) {
      rmw.liveliness_lease_duration = parse_duration( val, key );
      continue;
    }

    if ( key == "history" ) {
      rmw.history = parse_history( val.as<std::string>() );
      continue;
    }
    if ( key == "reliability" ) {
      rmw.reliability = parse_reliability( val.as<std::string>() );
      continue;
    }
    if ( key == "durability" ) {
      rmw.durability = parse_durability( val.as<std::string>() );
      continue;
    }
    if ( key == "liveliness" ) {
      rmw.liveliness = parse_liveliness( val.as<std::string>() );
      continue;
    }

    if ( key == "depth" ) {
      const int depth = val.as<int>();
      if ( depth < 0 ) {
        throw std::runtime_error( "'depth' may not be a negative value." );
      }
      rmw.depth = static_cast<size_t>( depth );
      continue;
    }
    if ( key == "avoid_ros_namespace_conventions" ) {
      rmw.avoid_ros_namespace_conventions = val.as<bool>();
      continue;
    }

    throw std::runtime_error( "Unexpected key '" + key + "' for QoS profile." );
  }

  rclcpp::QoSInitialization init( rmw.history, rmw.depth );
  return rclcpp::QoS( init, rmw );
}

std::unordered_map<std::string, rclcpp::QoS> convert_yaml_to_qos_overrides( const YAML::Node &root )
{
  if ( !root || !root.IsMap() ) {
    throw std::runtime_error( "QoS override YAML must be a map: <topic> -> <qos profile map>." );
  }

  std::unordered_map<std::string, rclcpp::QoS> out;
  for ( const auto &entry : root ) {
    const std::string topic = entry.first.as<std::string>();
    const YAML::Node &profile_node = entry.second;

    out.emplace( topic, interpret_node_as_qos( profile_node ) );
  }
  return out;
}

std::unordered_map<std::string, rclcpp::QoS> load_qos_overrides_from_file( const std::string &path )
{
  YAML::Node root = YAML::LoadFile( path );
  return convert_yaml_to_qos_overrides( root );
}

/**
 * @brief Formats memory size in human-readable units (B, KiB, MiB, etc.).
 * @param bytes The memory size in bytes.
 * @return A formatted string representing the memory size.
 */
std::string formatMemory( uint64_t bytes )
{
  if ( bytes < ( 1ull << 10 ) )
    return fmt::format( "{:.1f} B", static_cast<double>( bytes ) );
  else if ( bytes < ( 1ull << 20 ) )
    return fmt::format( "{:.1f} KiB", static_cast<double>( bytes ) / ( 1ull << 10 ) );
  else if ( bytes < ( 1ull << 30 ) )
    return fmt::format( "{:.1f} MiB", static_cast<double>( bytes ) / ( 1ull << 20 ) );
  else if ( bytes < ( 1ull << 40 ) )
    return fmt::format( "{:.1f} GiB", static_cast<double>( bytes ) / ( 1ull << 30 ) );
  else
    return fmt::format( "{:.1f} TiB", static_cast<double>( bytes ) / ( 1ull << 40 ) );
}

/**
 * @brief Converts a frequency value to a human-readable string (Hz, kHz, MHz).
 * @param rate The frequency in Hz.
 * @return A formatted string representing the frequency.
 */
std::string rateToString( double rate )
{
  if ( rate < 1000.0 )
    return fmt::format( "{:.1f} Hz", rate );
  else if ( rate < 1e6 )
    return fmt::format( "{:.1f} kHz", rate / 1e3 );
  else
    return fmt::format( "{:.1f} MHz", rate / 1e6 );
}

/**
 * @brief Converts a bytes per second to a human-readable string (B/s, KB/s, MB/s).
 * @param bandwidth The bandwidth in bytes per second.
 * @return A formatted string representing the bandwidth.
 */
std::string bandwidthToString( double bandwidth )
{
  if ( bandwidth < 1000.0 )
    return fmt::format( "{:.1f} B/s", bandwidth );
  else if ( bandwidth < 1000.0 * 1000.0 )
    return fmt::format( "{:.1f} kB/s", bandwidth / 1000.0 );
  else if ( bandwidth < 1000.0 * 1000.0 * 1000.0 )
    return fmt::format( "{:.1f} MB/s", bandwidth / ( 1000.0 * 1000.0 ) );
  else
    return fmt::format( "{:.1f} GB/s", bandwidth / ( 1000.0 * 1000.0 * 1000.0 ) );
}

int calculateRequiredLines( const std::vector<std::string> &lines )
{
  return static_cast<int>( lines.size() ) + 2; // +2 for borders
}

bool parseYamlNode( const YAML::Node &config, CustomOptions &custom_options,
                    rosbag2_transport::RecordOptions &record_options,
                    rosbag2_storage::StorageOptions &storage_options )
{
  if ( config["node_name"] ) {
    custom_options.node_name = config["node_name"].as<std::string>();
  }
    if ( config["output"] ) {
      storage_options.uri = config["output"].as<std::string>();
    }
    if ( config["storage_id"] ) {
      storage_options.storage_id = config["storage_id"].as<std::string>();
    }
    // mutually exclusive
    if ( config["max_bag_size"] && config["max_bag_size_gb"] ) {
      throw std::runtime_error( "Conflicting configuration detected: Both 'max_bag_size' and "
                                "'max_bag_size_gb' are defined. Please specify only one." );
    } else if ( config["max_bag_size"] ) {
      storage_options.max_bagfile_size = config["max_bag_size"].as<uint64_t>();
    } else if ( config["max_bag_size_gb"] ) {
      uint64_t max_bag_size_bytes =
          static_cast<uint64_t>( config["max_bag_size_gb"].as<float>() * 1024 * 1024 * 1024 );
      storage_options.max_bagfile_size = max_bag_size_bytes;
    }
    if ( config["max_bag_duration"] ) {
      storage_options.max_bagfile_duration = config["max_bag_duration"].as<uint64_t>();
    } else {
      storage_options.max_bagfile_duration = 0;
    }
    if ( config["max_cache_size"] ) {
      storage_options.max_cache_size = config["max_cache_size"].as<uint64_t>();
    } else {
      storage_options.max_cache_size = 0;
    }
    if ( config["storage_preset_profile"] ) {
      storage_options.storage_preset_profile = config["storage_preset_profile"].as<std::string>();
    }
    if ( config["storage_config_uri"] ) {
      storage_options.storage_config_uri = config["storage_config_uri"].as<std::string>();
    }
    if ( config["snapshot_mode"] ) {
      storage_options.snapshot_mode = config["snapshot_mode"].as<bool>();
    } else {
      storage_options.snapshot_mode = false;
    }
    if ( config["start_time_ns"] ) {
      storage_options.start_time_ns = config["start_time_ns"].as<int64_t>();
    } else {
      storage_options.start_time_ns = -1;
    }
    if ( config["end_time_ns"] ) {
      storage_options.end_time_ns = config["end_time_ns"].as<int64_t>();
    } else {
      storage_options.end_time_ns = -1;
    }
    if ( config["custom_data"] ) {
      storage_options.custom_data.clear();
      for ( const auto &pair : config["custom_data"] ) {
        if ( pair.size() != 2 ) {
          std::cerr << "Error: Custom data must be a map of key-value pairs." << std::endl;
          return false; // Invalid custom data format
        }
        storage_options.custom_data[pair[0].as<std::string>()] = pair[1].as<std::string>();
      }
    }

    if ( config["all_topics"] ) {
      record_options.all_topics = config["all_topics"].as<bool>();
    } else {
      record_options.all_topics = false;
    }
    if ( config["all_services"] ) {
      record_options.all_services = config["all_services"].as<bool>();
    } else {
      record_options.all_services = false;
    }
    if ( config["is_discovery_disabled"] ) {
      record_options.is_discovery_disabled = config["is_discovery_disabled"].as<bool>();
    } else {
      record_options.is_discovery_disabled = false;
    }
    if ( config["topics"] ) {
      record_options.topics = config["topics"].as<std::vector<std::string>>();
    }
    if ( config["topic_types"] ) {
      record_options.topic_types = config["topic_types"].as<std::vector<std::string>>();
    }
    if ( config["services"] ) {
      record_options.services = config["services"].as<std::vector<std::string>>();
    }
    if ( config["exclude_topics"] ) {
      record_options.exclude_topics = config["exclude_topics"].as<std::vector<std::string>>();
    }
    if ( config["exclude_topic_types"] ) {
      record_options.exclude_topic_types =
          config["exclude_topic_types"].as<std::vector<std::string>>();
    }
    if ( config["exclude_service_events"] ) {
      record_options.exclude_service_events =
          config["exclude_service_events"].as<std::vector<std::string>>();
    }
    if ( config["rmw_serialization_format"] ) {
      record_options.rmw_serialization_format = config["rmw_serialization_format"].as<std::string>();
    } else {
      record_options.rmw_serialization_format = rmw_get_serialization_format();
    }
    if ( config["topic_polling_interval"] ) {
      record_options.topic_polling_interval =
          std::chrono::milliseconds( config["topic_polling_interval"].as<int>() );
    } else {
      record_options.topic_polling_interval = std::chrono::milliseconds( 100 );
    }
    if ( config["regex"] ) {
      record_options.regex = config["regex"].as<std::string>();
    }
    if ( config["exclude_regex"] ) {
      record_options.exclude_regex = config["exclude_regex"].as<std::string>();
    }
    if ( config["node_prefix"] ) {
      record_options.node_prefix = config["node_prefix"].as<std::string>();
    }
    if ( config["compression_mode"] ) {
      record_options.compression_mode = config["compression_mode"].as<std::string>();
    }
    if ( config["compression_format"] ) {
      record_options.compression_format = config["compression_format"].as<std::string>();
    }
    if ( config["compression_queue_size"] ) {
      record_options.compression_queue_size = config["compression_queue_size"].as<uint64_t>();
    } else {
      record_options.compression_queue_size = 0;
    }
    if ( config["compression_threads"] ) {
      record_options.compression_threads = config["compression_threads"].as<uint64_t>();
    } else {
      record_options.compression_threads = 0;
    }
    if ( config["compression_threads_priority"] ) {
      record_options.compression_threads_priority =
          config["compression_threads_priority"].as<int32_t>();
    } else {
      record_options.compression_threads_priority = 0;
    }
    if ( config["topic_qos_profile_overrides_path"] ) {
      record_options.topic_qos_profile_overrides = hector_recorder::load_qos_overrides_from_file(
          config["topic_qos_profile_overrides_path"].as<std::string>() );
    }
    if ( config["include_hidden_topics"] ) {
      record_options.include_hidden_topics = config["include_hidden_topics"].as<bool>();
    } else {
      record_options.include_hidden_topics = false;
    }
    if ( config["include_unpublished_topics"] ) {
      record_options.include_unpublished_topics = config["include_unpublished_topics"].as<bool>();
    } else {
      record_options.include_unpublished_topics = false;
    }
    if ( config["ignore_leaf_topics"] ) {
      record_options.ignore_leaf_topics = config["ignore_leaf_topics"].as<bool>();
    } else {
      record_options.ignore_leaf_topics = false;
    }
    if ( config["start_paused"] ) {
      record_options.start_paused = config["start_paused"].as<bool>();
    } else {
      record_options.start_paused = false;
    }
    if ( config["use_sim_time"] ) {
      record_options.use_sim_time = config["use_sim_time"].as<bool>();
    } else {
      record_options.use_sim_time = false;
    }
    if ( config["disable_keyboard_controls"] ) {
      record_options.disable_keyboard_controls = config["disable_keyboard_controls"].as<bool>();
    } else {
      record_options.disable_keyboard_controls = false;
    }
    if ( config["publish_status"] ) {
      custom_options.publish_status = config["publish_status"].as<bool>();
    }
    if ( config["publish_status_topic"] ) {
      custom_options.status_topic = config["publish_status_topic"].as<std::string>();
    }

    // Parse topic throttle configuration
    if ( config["topic_throttle"] ) {
      const YAML::Node &throttle_node = config["topic_throttle"];
      if ( !throttle_node.IsMap() ) {
        throw std::runtime_error( "'topic_throttle' must be a map: <topic> -> {type, ...}" );
      }
      for ( const auto &entry : throttle_node ) {
        const std::string topic = entry.first.as<std::string>();
        const YAML::Node &cfg = entry.second;
        ThrottleConfig tc;

        std::string type_str = cfg["type"].as<std::string>( "messages" );
        if ( type_str == "messages" ) {
          tc.type = ThrottleConfig::MESSAGES;
          if ( !cfg["msgs_per_sec"] ) {
            throw std::runtime_error( "topic_throttle: '" + topic +
                                      "' has type 'messages' but no 'msgs_per_sec'." );
          }
          tc.msgs_per_sec = cfg["msgs_per_sec"].as<double>();
          if ( tc.msgs_per_sec <= 0.0 ) {
            throw std::runtime_error( "topic_throttle: '" + topic + "' msgs_per_sec must be > 0." );
          }
        } else if ( type_str == "bytes" ) {
          tc.type = ThrottleConfig::BYTES;
          if ( !cfg["bytes_per_sec"] ) {
            throw std::runtime_error( "topic_throttle: '" + topic +
                                      "' has type 'bytes' but no 'bytes_per_sec'." );
          }
          tc.bytes_per_sec = cfg["bytes_per_sec"].as<int64_t>();
          if ( tc.bytes_per_sec <= 0 ) {
            throw std::runtime_error( "topic_throttle: '" + topic + "' bytes_per_sec must be > 0." );
          }
          tc.window = cfg["window"].as<double>( 1.0 );
          if ( tc.window <= 0.0 ) {
            throw std::runtime_error( "topic_throttle: '" + topic + "' window must be > 0." );
          }
        } else {
          throw std::runtime_error( "topic_throttle: '" + topic + "' has unknown type '" +
                                    type_str + "'. Expected 'messages' or 'bytes'." );
        }
        custom_options.topic_throttle[topic] = tc;
      }
    }

    if ( record_options.rmw_serialization_format.empty() ) {
      record_options.rmw_serialization_format =
          rmw_get_serialization_format();
    }

    return true;
}

bool parseYamlConfig( CustomOptions &custom_options, rosbag2_transport::RecordOptions &record_options,
                      rosbag2_storage::StorageOptions &storage_options )
{
  try {
    YAML::Node config = YAML::LoadFile( custom_options.config_path );
    return parseYamlNode( config, custom_options, record_options, storage_options );
  } catch ( const std::exception &e ) {
    RCLCPP_ERROR( rclcpp::get_logger( "hector_recorder.config.yaml" ),
                  "Error parsing YAML config: %s", e.what() );
    return false;
  }
}

bool parseYamlConfigFromString( const std::string &yaml_string, CustomOptions &custom_options,
                                rosbag2_transport::RecordOptions &record_options,
                                rosbag2_storage::StorageOptions &storage_options )
{
  try {
    YAML::Node config = YAML::Load( yaml_string );
    return parseYamlNode( config, custom_options, record_options, storage_options );
  } catch ( const std::exception &e ) {
    RCLCPP_ERROR( rclcpp::get_logger( "hector_recorder.config.yaml" ),
                  "Error parsing YAML config from string: %s", e.what() );
    return false;
  }
}

std::string serializeConfigToYaml( const CustomOptions &custom_options,
                                   const rosbag2_transport::RecordOptions &record_options,
                                   const rosbag2_storage::StorageOptions &storage_options,
                                   const std::string &output_override )
{
  YAML::Emitter out;
  out << YAML::BeginMap;

  out << YAML::Key << "node_name" << YAML::Value << custom_options.node_name;
  out << YAML::Key << "output" << YAML::Value
      << ( output_override.empty() ? storage_options.uri : output_override );
  out << YAML::Key << "storage_id" << YAML::Value << storage_options.storage_id;

  if ( storage_options.max_bagfile_size > 0 ) {
    out << YAML::Key << "max_bag_size" << YAML::Value << storage_options.max_bagfile_size;
  }
  if ( storage_options.max_bagfile_duration > 0 ) {
    out << YAML::Key << "max_bag_duration" << YAML::Value << storage_options.max_bagfile_duration;
  }
  if ( storage_options.max_cache_size > 0 ) {
    out << YAML::Key << "max_cache_size" << YAML::Value << storage_options.max_cache_size;
  }
  if ( !storage_options.storage_preset_profile.empty() ) {
    out << YAML::Key << "storage_preset_profile" << YAML::Value
        << storage_options.storage_preset_profile;
  }
  if ( !storage_options.storage_config_uri.empty() ) {
    out << YAML::Key << "storage_config_uri" << YAML::Value << storage_options.storage_config_uri;
  }
  out << YAML::Key << "snapshot_mode" << YAML::Value << storage_options.snapshot_mode;

  out << YAML::Key << "all_topics" << YAML::Value << record_options.all_topics;
  out << YAML::Key << "all_services" << YAML::Value << record_options.all_services;

  if ( !record_options.topics.empty() ) {
    out << YAML::Key << "topics" << YAML::Value << record_options.topics;
  }
  if ( !record_options.topic_types.empty() ) {
    out << YAML::Key << "topic_types" << YAML::Value << record_options.topic_types;
  }
  if ( !record_options.services.empty() ) {
    out << YAML::Key << "services" << YAML::Value << record_options.services;
  }
  if ( !record_options.exclude_topics.empty() ) {
    out << YAML::Key << "exclude_topics" << YAML::Value << record_options.exclude_topics;
  }
  if ( !record_options.exclude_topic_types.empty() ) {
    out << YAML::Key << "exclude_topic_types" << YAML::Value << record_options.exclude_topic_types;
  }
  if ( !record_options.exclude_service_events.empty() ) {
    out << YAML::Key << "exclude_service_events" << YAML::Value
        << record_options.exclude_service_events;
  }

  out << YAML::Key << "rmw_serialization_format" << YAML::Value
      << record_options.rmw_serialization_format;

  if ( !record_options.regex.empty() ) {
    out << YAML::Key << "regex" << YAML::Value << record_options.regex;
  }
  if ( !record_options.exclude_regex.empty() ) {
    out << YAML::Key << "exclude_regex" << YAML::Value << record_options.exclude_regex;
  }
  if ( !record_options.compression_mode.empty() ) {
    out << YAML::Key << "compression_mode" << YAML::Value << record_options.compression_mode;
  }
  if ( !record_options.compression_format.empty() ) {
    out << YAML::Key << "compression_format" << YAML::Value << record_options.compression_format;
  }

  out << YAML::Key << "publish_status" << YAML::Value << custom_options.publish_status;
  out << YAML::Key << "publish_status_topic" << YAML::Value << custom_options.status_topic;

  // Throttle configs
  if ( !custom_options.topic_throttle.empty() ) {
    out << YAML::Key << "topic_throttle" << YAML::Value << YAML::BeginMap;
    for ( const auto &[topic, tc] : custom_options.topic_throttle ) {
      out << YAML::Key << topic << YAML::Value << YAML::BeginMap;
      if ( tc.type == ThrottleConfig::MESSAGES ) {
        out << YAML::Key << "type" << YAML::Value << "messages";
        out << YAML::Key << "msgs_per_sec" << YAML::Value << tc.msgs_per_sec;
      } else {
        out << YAML::Key << "type" << YAML::Value << "bytes";
        out << YAML::Key << "bytes_per_sec" << YAML::Value << tc.bytes_per_sec;
        out << YAML::Key << "window" << YAML::Value << tc.window;
      }
      out << YAML::EndMap;
    }
    out << YAML::EndMap;
  }

  out << YAML::EndMap;
  return std::string( out.c_str() );
}

std::string clipString( const std::string &str, int max_length )
{
  if ( static_cast<int>( str.size() ) <= max_length ) {
    return str;
  }

  // Find the position of the last '/'
  size_t last_slash_pos = str.rfind( '/' );
  if ( last_slash_pos == std::string::npos || last_slash_pos == 0 ) {
    // If no '/' is found or it's the first character, fallback to simple clipping
    return str.substr( 0, max_length - 3 ) + "...";
  }

  std::string suffix = str.substr( last_slash_pos ); // Include the '/' in the suffix
  int suffix_length = static_cast<int>( suffix.size() );
  int prefix_length = max_length - suffix_length - 3; // Account for "..."

  if ( prefix_length <= 0 ) {
    // If the suffix alone exceeds the max length, truncate it
    return "..." + suffix.substr( suffix.size() - ( max_length - 3 ) );
  }

  std::string prefix = str.substr( 0, prefix_length );
  return prefix + "..." + suffix;
}

void ensureLeadingSlash( std::vector<std::string> &vector )
{
  if ( !vector.empty() ) {
    for ( auto &string : vector ) {
      if ( string.find( "/" ) != 0 ) {
        string = "/" + string;
      }
    }
  }
}

static std::string expandUserAndEnv( std::string s )
{
  // ~ → $HOME
  if ( !s.empty() && s[0] == '~' ) {
    const char *home = std::getenv( "HOME" );
    if ( home && s.size() == 1 ) {
      s = home;
    } else if ( home && s.size() > 1 && s[1] == '/' ) {
      s = std::string( home ) + s.substr( 1 );
    }
    // (If "~user" needed, implement lookup; omitted for simplicity.)
  }

  // ${VAR} → env, then $VAR → env
  auto replace_env = []( const std::string &in, const std::regex &re ) {
    std::string out;
    std::sregex_iterator it( in.begin(), in.end(), re ), end;
    size_t last = 0;
    out.reserve( in.size() );
    for ( ; it != end; ++it ) {
      out.append( in, last, it->position() - last );
      std::string key = it->size() > 1 ? ( *it )[1].str() : "";
      const char *val = key.empty() ? nullptr : std::getenv( key.c_str() );
      out += ( val ? val : "" );
      last = it->position() + it->length();
    }
    out.append( in, last, std::string::npos );
    return out;
  };

  // ${VAR}
  s = replace_env( s, std::regex( R"(\$\{([A-Za-z_][A-Za-z0-9_]*)\})" ) );
  // $VAR
  s = replace_env( s, std::regex( R"(\$([A-Za-z_][A-Za-z0-9_]*))" ) );

  return s;
}

std::string resolveOutputUriToAbsolute( const std::string &uri )
{
  std::string expanded = expandUserAndEnv( uri );
  fs::path p( expanded );

  // Make absolute and normalize. weakly_canonical doesn't require existence.
  fs::path abs = fs::absolute( p );
  fs::path norm = fs::weakly_canonical( abs );

  return norm.empty() ? abs.string() : norm.string();
}

// ========================================================================
// Shared service handler implementations
// ========================================================================

void fillRecorderStatus( hector_recorder_msgs::msg::RecorderStatus &status_msg,
                         RecorderImpl *recorder, const CustomOptions &custom_options,
                         const rosbag2_storage::StorageOptions &storage_options,
                         const rosbag2_transport::RecordOptions &record_options,
                         rclcpp::Node *node, const std::string &raw_output_uri )
{
  status_msg.output_dir = storage_options.uri;
  status_msg.config_path = custom_options.config_path;
  status_msg.node_name = node->get_fully_qualified_name();

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

  // Available topics on the ROS graph
  auto all_topics = node->get_topic_names_and_types();
  for ( const auto &[name, types] : all_topics ) {
    status_msg.available_topics.push_back( name );
  }

  // Current config as YAML (use raw base path so restarts resolve fresh directories)
  status_msg.config_yaml =
      serializeConfigToYaml( custom_options, record_options, storage_options, raw_output_uri );
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
                           const std::string &request_output_dir, rclcpp::Node *node,
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
      // Hot update: update topic filter and restart discovery to pick up new topics
      recorder->update_record_options( record_options );
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

} // namespace hector_recorder