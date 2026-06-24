#include "hector_recorder/config_yaml.h"

namespace hector_recorder
{

// ========================================================================
// QoS override parsing helpers
// ========================================================================

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

// ========================================================================
// Config YAML parsing
// ========================================================================

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

// ========================================================================
// Config YAML serialization
// ========================================================================

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

} // namespace hector_recorder
