#pragma once

#include <deque>
#include <mutex>
#include <string>
#include <unordered_map>

#include <rclcpp/clock.hpp>

namespace hector_recorder
{

/**
 * @brief Configuration for throttling a single topic, inspired by ros2 topic tools: https://github.com/ros-tooling/topic_tools
 */
struct ThrottleConfig {
  enum Type { MESSAGES, BYTES, FREQUENCY };

  Type type = MESSAGES;
  double msgs_per_sec = 0.0; ///< Max messages per second (for MESSAGES type)
  int64_t bytes_per_sec = 0; ///< Max bytes per second (for BYTES type)
  double window = 1.0;       ///< Sliding window in seconds (for BYTES type)
  double frequency_hz = 0.0; ///< Target frequency with evenly spaced output (for FREQUENCY type)
};

struct ThrottleState {
  rclcpp::Time last_time{ 0, 0, RCL_SYSTEM_TIME };
  rclcpp::Time frequency_next_time{ 0, 0, RCL_SYSTEM_TIME };
  rclcpp::Time frequency_last_call_time{ 0, 0, RCL_SYSTEM_TIME };

  /// Sliding window of (timestamp_seconds, message_size) pairs
  std::deque<std::pair<double, size_t>> sent_deque;
};

using ThrottleConfigMap = std::unordered_map<std::string, ThrottleConfig>;

} // namespace hector_recorder
