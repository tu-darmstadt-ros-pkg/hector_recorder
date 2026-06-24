#ifndef HECTOR_RECORDER_CONFIG_YAML_H
#define HECTOR_RECORDER_CONFIG_YAML_H

#include "hector_recorder/utils.h"

#include <rclcpp/qos.hpp>
#include <string>
#include <unordered_map>

namespace hector_recorder
{

// ========================================================================
// QoS override parsing
// ========================================================================

std::unordered_map<std::string, rclcpp::QoS> convert_yaml_to_qos_overrides( const YAML::Node &root );
std::unordered_map<std::string, rclcpp::QoS> load_qos_overrides_from_file( const std::string &path );

// ========================================================================
// Config YAML parsing and serialization
// ========================================================================

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

} // namespace hector_recorder

#endif // HECTOR_RECORDER_CONFIG_YAML_H
