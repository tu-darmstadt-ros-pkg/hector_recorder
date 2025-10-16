// Copyright 2018 Open Source Robotics Foundation, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Changelog Jonathan Lichtenfeld 12.6.2024:
// - Extract RecorderImpl from rosbag2_transport/recorder.cpp to its own file
// - Add get_topics_names_to_info() 
// - Add get_bagfile_duration()


#include "hector_recorder/modified/recorder_impl.hpp"
#include "rosbag2_cpp/writers/sequential_writer.hpp"

namespace hector_recorder
{

RecorderImpl::RecorderImpl(
  rclcpp::Node * owner,
  std::shared_ptr<rosbag2_cpp::Writer> writer,
  const rosbag2_storage::StorageOptions & storage_options,
  const rosbag2_transport::RecordOptions & record_options)
: writer_(std::move(writer)),
  storage_options_(storage_options),
  record_options_(record_options),
  node(owner)
{
  if (record_options_.use_sim_time && record_options_.is_discovery_disabled) {
    throw std::runtime_error(
            "use_sim_time and is_discovery_disabled both set, but are incompatible settings. "
            "The /clock topic needs to be discovered to record with sim time.");
  }

  topic_filter_ = std::make_unique<rosbag2_transport::TopicFilter>(record_options, node->get_node_graph_interface());

  for (auto & topic : record_options_.topics) {
    topic = rclcpp::expand_topic_or_service_name(
      topic, node->get_name(),
      node->get_namespace(), false);
  }

  for (auto & exclude_topic : record_options_.exclude_topics) {
    exclude_topic = rclcpp::expand_topic_or_service_name(
      exclude_topic, node->get_name(),
      node->get_namespace(), false);
  }

  for (auto & service : record_options_.services) {
    service = rclcpp::expand_topic_or_service_name(
      service, node->get_name(),
      node->get_namespace(), false);
  }

  for (auto & exclude_service_event_topic : record_options_.exclude_service_events) {
    exclude_service_event_topic = rclcpp::expand_topic_or_service_name(
      exclude_service_event_topic, node->get_name(),
      node->get_namespace(), false);
  }
}

RecorderImpl::~RecorderImpl()
{
  stop();
}

void RecorderImpl::stop()
{
  std::lock_guard<std::mutex> state_lock(start_stop_transition_mutex_);
  if (!in_recording_) {
    RCLCPP_DEBUG(node->get_logger(), "Recording has already been stopped or not running.");
    return;
  }

  stop_discovery();
  pause();
  subscriptions_.clear();
  writer_->close();  // Call writer->close() to finalize current bag file and write metadata

  {
    std::lock_guard<std::mutex> lock(event_publisher_thread_mutex_);
    event_publisher_thread_should_exit_ = true;
  }
  event_publisher_thread_wake_cv_.notify_all();
  if (event_publisher_thread_.joinable()) {
    event_publisher_thread_.join();
  }
  in_recording_ = false;
  RCLCPP_INFO(node->get_logger(), "Recording stopped");
}

void RecorderImpl::record()
{
  std::lock_guard<std::mutex> state_lock(start_stop_transition_mutex_);
  if (in_recording_.exchange(true)) {
    RCLCPP_WARN_STREAM(
      node->get_logger(),
      "Called Recorder::record() while already in recording, dismissing request.");
    return;
  }
  paused_ = false;
  topic_qos_profile_overrides_ = record_options_.topic_qos_profile_overrides;
  if (record_options_.rmw_serialization_format.empty()) {
    throw std::runtime_error("No serialization format specified!");
  }

  writer_->open(
    storage_options_,
    {rmw_get_serialization_format(), record_options_.rmw_serialization_format});

  files_.push_back(storage_options_.uri); // Add the first file to the list
  split_event_pub_ =
    node->create_publisher<rosbag2_interfaces::msg::WriteSplitEvent>("events/write_split", 1);

  // Start the thread that will publish events
  event_publisher_thread_ = std::thread(&RecorderImpl::event_publisher_thread_main, this);

  rosbag2_cpp::bag_events::WriterEventCallbacks callbacks;
  callbacks.write_split_callback =
    [this](rosbag2_cpp::bag_events::BagSplitInfo & info) {
      {
        std::lock_guard<std::mutex> lock(event_publisher_thread_mutex_);
        bag_split_info_ = info;
        write_split_has_occurred_ = true;
      }
      event_publisher_thread_wake_cv_.notify_all();
    };
  writer_->add_event_callbacks(callbacks);

  serialization_format_ = record_options_.rmw_serialization_format;
  RCLCPP_INFO(node->get_logger(), "Listening for topics...");
  if (!record_options_.use_sim_time) {
    subscribe_topics(get_requested_or_available_topics());
  }

  // Insert all requested topics into topics_info_ to ensure they are tracked
  auto unknown_topics = get_unknown_topics();
  for (const auto & t : unknown_topics) {
    topics_info_[t];
  }
  if (!record_options_.is_discovery_disabled) {
    start_discovery();
  }
}

void RecorderImpl::split()
{
  writer_->split_bagfile();
}

void RecorderImpl::event_publisher_thread_main()
{
  RCLCPP_INFO(node->get_logger(), "Event publisher thread: Starting");
  while (!event_publisher_thread_should_exit_.load()) {
    std::unique_lock<std::mutex> lock(event_publisher_thread_mutex_);
    event_publisher_thread_wake_cv_.wait(
      lock,
      [this] {return event_publisher_thread_should_wake();});

    if (write_split_has_occurred_) {
      write_split_has_occurred_ = false;

      auto message = rosbag2_interfaces::msg::WriteSplitEvent();
      message.closed_file = bag_split_info_.closed_file;
      message.opened_file = bag_split_info_.opened_file;
      message.node_name = node->get_fully_qualified_name();
      files_.push_back(message.opened_file);
      try {
        split_event_pub_->publish(message);
      } catch (const std::exception & e) {
        RCLCPP_ERROR_STREAM(
          node->get_logger(),
          "Failed to publish message on '/events/write_split' topic. \nError: " << e.what());
      } catch (...) {
        RCLCPP_ERROR_STREAM(
          node->get_logger(),
          "Failed to publish message on '/events/write_split' topic.");
      }
    }
  }
  RCLCPP_INFO(node->get_logger(), "Event publisher thread: Exiting");
}

bool RecorderImpl::event_publisher_thread_should_wake()
{
  return write_split_has_occurred_ || event_publisher_thread_should_exit_;
}

const rosbag2_cpp::Writer & RecorderImpl::get_writer_handle()
{
  return *writer_;
}

void RecorderImpl::pause()
{
  if (paused_.exchange(true)) {
    RCLCPP_DEBUG(node->get_logger(), "Recorder is already in pause state.");
  } else {
    RCLCPP_INFO_STREAM(node->get_logger(), "Pausing recording.");
  }
}

void RecorderImpl::start_discovery()
{
  std::lock_guard<std::mutex> state_lock(discovery_mutex_);
  if (stop_discovery_.exchange(false)) {
    RCLCPP_DEBUG(node->get_logger(), "Recorder topic discovery is already running.");
  } else {
    discovery_future_ =
      std::async(std::launch::async, std::bind(&RecorderImpl::topics_discovery, this));
  }
}

void RecorderImpl::stop_discovery()
{
  std::lock_guard<std::mutex> state_lock(discovery_mutex_);
  if (stop_discovery_.exchange(true)) {
    RCLCPP_DEBUG(
      node->get_logger(), "Recorder topic discovery has already been stopped or not running.");
  } else {
    if (discovery_future_.valid()) {
      auto status = discovery_future_.wait_for(2 * record_options_.topic_polling_interval);
      if (status != std::future_status::ready) {
        RCLCPP_ERROR_STREAM(
          node->get_logger(),
          "discovery_future_.wait_for(" << record_options_.topic_polling_interval.count() <<
            ") return status: " <<
            (status == std::future_status::timeout ? "timeout" : "deferred"));
      }
    }
  }
}


void RecorderImpl::topics_discovery()
{
  // If using sim time - wait until /clock topic received before even creating subscriptions
  if (record_options_.use_sim_time) {
    RCLCPP_INFO(
      node->get_logger(),
      "use_sim_time set, waiting for /clock before starting recording...");
    while (rclcpp::ok() && stop_discovery_ == false) {
      if (node->get_clock()->wait_until_started(record_options_.topic_polling_interval)) {
        break;
      }
    }
    if (node->get_clock()->started()) {
      RCLCPP_INFO(node->get_logger(), "Sim time /clock found, starting recording.");
    }
  }
  while (rclcpp::ok() && stop_discovery_ == false) {
    try {
      auto topics_to_subscribe = get_requested_or_available_topics();
      for (const auto & topic_and_type : topics_to_subscribe) {
        warn_if_new_qos_for_subscribed_topic(topic_and_type.first);
      }
      auto missing_topics = get_missing_topics(topics_to_subscribe);
      subscribe_topics(missing_topics);

      // Update topic publisher info
      update_topic_publisher_info();

      if (!record_options_.topics.empty() &&
        subscriptions_.size() == record_options_.topics.size())
      {
        RCLCPP_INFO(
          node->get_logger(),
          "All requested topics are subscribed. Stopping discovery...");
        return;
      }
    } catch (const std::exception & e) {
      RCLCPP_ERROR_STREAM(node->get_logger(), "Failure in topics discovery.\nError: " << e.what());
    } catch (...) {
      RCLCPP_ERROR_STREAM(node->get_logger(), "Failure in topics discovery.");
    }
    std::this_thread::sleep_for(record_options_.topic_polling_interval);
  }
}

std::unordered_map<std::string, std::string>
RecorderImpl::get_requested_or_available_topics()
{
  auto all_topics_and_types = node->get_topic_names_and_types();
  return topic_filter_->filter_topics(all_topics_and_types);
}

std::vector<std::string> RecorderImpl::get_unknown_topics() const
{
  std::vector<std::string> unknown_topics;
  for (const auto & topic : record_options_.topics) {
    if (subscriptions_.find(topic) == subscriptions_.end()) {
      unknown_topics.push_back(topic);
    }
  }
  return unknown_topics;
}

std::unordered_map<std::string, std::string>
RecorderImpl::get_missing_topics(const std::unordered_map<std::string, std::string> & all_topics)
{
  std::unordered_map<std::string, std::string> missing_topics;
  for (const auto & i : all_topics) {    
    if (subscriptions_.find(i.first) == subscriptions_.end()) {
      missing_topics.emplace(i.first, i.second);
    }
  }
  return missing_topics;
}


void RecorderImpl::subscribe_topics(
  const std::unordered_map<std::string, std::string> & topics_and_types)
{
  for (const auto & topic_with_type : topics_and_types) {
    auto endpoint_infos = node->get_publishers_info_by_topic(topic_with_type.first);
    subscribe_topic(
      {
        0u,
        topic_with_type.first,
        topic_with_type.second,
        serialization_format_,
        offered_qos_profiles_for_topic(endpoint_infos),
        type_description_hash_for_topic(endpoint_infos),
      });
  }
}

void RecorderImpl::subscribe_topic(const rosbag2_storage::TopicMetadata & topic)
{
  // Need to create topic in writer before we are trying to create subscription. Since in
  // callback for subscription we are calling writer_->write(bag_message); and it could happened
  // that callback called before we reached out the line: writer_->create_topic(topic)
  writer_->create_topic(topic);

  rosbag2_storage::Rosbag2QoS subscription_qos{subscription_qos_for_topic(topic.name)};

  auto subscription = create_subscription(topic.name, topic.type, subscription_qos);
  if (subscription) {
    subscriptions_.insert({topic.name, subscription});
    topics_info_[topic.name];
    RCLCPP_INFO_STREAM(
      node->get_logger(),
      "Subscribed to topic '" << topic.name << "'");
  } else {
    writer_->remove_topic(topic);
    subscriptions_.erase(topic.name);
  }
}

std::shared_ptr<rclcpp::GenericSubscription>
RecorderImpl::create_subscription(
  const std::string & topic_name, const std::string & topic_type, const rclcpp::QoS & qos)
{
#ifdef _WIN32
  if (std::string(rmw_get_implementation_identifier()).find("rmw_connextdds") !=
    std::string::npos)
  {
    return node->create_generic_subscription(
      topic_name,
      topic_type,
      qos,
      [this, topic_name, topic_type](std::shared_ptr<const rclcpp::SerializedMessage> message,
      const rclcpp::MessageInfo &) {
        if (!paused_.load()) {
          update_topic_statistics(topic_name, std::chrono::nanoseconds(mi.get_rmw_message_info().received_timestamp), message->size());
          writer_->write(
            std::move(message), topic_name, topic_type, node->now().nanoseconds(),
            0);
        }
      });
  }
#endif

  if (record_options_.use_sim_time) {
    return node->create_generic_subscription(
      topic_name,
      topic_type,
      qos,
      [this, topic_name, topic_type](std::shared_ptr<const rclcpp::SerializedMessage> message,
      const rclcpp::MessageInfo & mi) {
        if (!paused_.load()) {
            update_topic_statistics(topic_name, std::chrono::nanoseconds(mi.get_rmw_message_info().received_timestamp), message->size());
            writer_->write(
            std::move(message), topic_name, topic_type, node->now().nanoseconds(),
            mi.get_rmw_message_info().source_timestamp);
        }
      });
  } else {
    return node->create_generic_subscription(
      topic_name,
      topic_type,
      qos,
      [this, topic_name, topic_type](std::shared_ptr<const rclcpp::SerializedMessage> message,
      const rclcpp::MessageInfo & mi) {
        if (!paused_.load()) {
          update_topic_statistics(topic_name, std::chrono::nanoseconds(mi.get_rmw_message_info().received_timestamp), message->size());
          writer_->write(
            std::move(message), topic_name, topic_type,
            mi.get_rmw_message_info().received_timestamp,
            mi.get_rmw_message_info().source_timestamp);
        }
      });
  }
}

void RecorderImpl::update_topic_statistics(
  const std::string & topic_name, std::chrono::nanoseconds stamp, int size)
{
  if (!first_msg_received_) {                        
    first_stamp_ = node->now();
    first_msg_received_ = true;
  }
  topics_info_[topic_name].update_statistics(stamp, size);
}

void RecorderImpl::update_topic_publisher_info() {
  for (auto &topic_info : topics_info_) {
    const auto &topic_name = topic_info.first;
    auto &info = topic_info.second;
    auto endpoint_infos = node->get_publishers_info_by_topic(topic_name);
    if (!endpoint_infos.empty()) {
      std::string topic_type = endpoint_infos[0].topic_type();
      int publisher_count = endpoint_infos.size();
      std::string qos = reliability_to_string(
        endpoint_infos[0].qos_profile().reliability());      
      info.update_publisher_info(topic_type, publisher_count, qos);
    } else {
      info.update_publisher_info("Unknown", 0, "Unknown");
    }
  }
}

std::vector<rclcpp::QoS> RecorderImpl::offered_qos_profiles_for_topic(
  const std::vector<rclcpp::TopicEndpointInfo> & topics_endpoint_info) const
{
  std::vector<rclcpp::QoS> offered_qos_profiles;
  for (const auto & info : topics_endpoint_info) {
    offered_qos_profiles.push_back(info.qos_profile());
  }
  return offered_qos_profiles;
}

const std::unordered_map<std::string, TopicInformation>& RecorderImpl::get_topics_info() {
    if (record_options_.is_discovery_disabled) {
        update_topic_publisher_info();
    }
    return topics_info_;
}

const rclcpp::Duration RecorderImpl::get_bagfile_duration() const
{
  if (!first_msg_received_) {
    return rclcpp::Duration(0, 0);
  }
  return rclcpp::Duration(node->now() - first_stamp_);
}

const uint64_t RecorderImpl::get_bagfile_size() const
{
  size_t total_size = 0;
  for (const auto & topic_info : topics_info_) {
    total_size += topic_info.second.size();
  }
  return total_size;
}

const std::vector<std::string> & RecorderImpl::get_files() const
{
  return files_;
}

std::string type_hash_to_string(const rosidl_type_hash_t & type_hash)
{
  if (type_hash.version == 0) {
    // version is unset, this is an empty type hash.
    return "";
  }
  if (type_hash.version > 1) {
    // this is a version we don't know how to serialize
    ROSBAG2_TRANSPORT_LOG_WARN_STREAM(
      "attempted to stringify type hash with unknown version " << type_hash.version);
    return "";
  }
  rcutils_allocator_t allocator = rcutils_get_default_allocator();
  char * stringified_type_hash = nullptr;
  rcutils_ret_t status = rosidl_stringify_type_hash(&type_hash, allocator, &stringified_type_hash);
  std::string result = "";
  if (status == RCUTILS_RET_OK) {
    result = stringified_type_hash;
  }
  if (stringified_type_hash != nullptr) {
    allocator.deallocate(stringified_type_hash, allocator.state);
  }
  return result;
}

std::string type_description_hash_for_topic(
  const std::vector<rclcpp::TopicEndpointInfo> & topics_endpoint_info)
{
  rosidl_type_hash_t result_hash = rosidl_get_zero_initialized_type_hash();
  for (const auto & info : topics_endpoint_info) {
    // If all endpoint infos provide the same type hash, return it. Otherwise return an empty
    // string to signal that the type description hash for this topic cannot be determined.
    rosidl_type_hash_t endpoint_hash = info.topic_type_hash();
    if (endpoint_hash.version == 0) {
      continue;
    }
    if (result_hash.version == 0) {
      result_hash = endpoint_hash;
      continue;
    }
    bool difference_detected = (endpoint_hash.version != result_hash.version);
    difference_detected |= (
      0 != memcmp(endpoint_hash.value, result_hash.value, ROSIDL_TYPE_HASH_SIZE));
    if (difference_detected) {
      std::string result_string = type_hash_to_string(result_hash);
      std::string endpoint_string = type_hash_to_string(endpoint_hash);
      ROSBAG2_TRANSPORT_LOG_WARN_STREAM(
        "type description hashes for topic type '" << info.topic_type() << "' conflict: '" <<
          result_string << "' != '" << endpoint_string << "'");
      return "";
    }
  }
  return type_hash_to_string(result_hash);
}

std::string reliability_to_string(
  const rclcpp::ReliabilityPolicy & reliability)
{
  switch (reliability) {
    case rclcpp::ReliabilityPolicy::BestEffort:
      return "Best Effort";
    case rclcpp::ReliabilityPolicy::Reliable:
      return "Reliable";
    case rclcpp::ReliabilityPolicy::SystemDefault:
      return "System Default";
    default:
      return "Unknown";
  }
}

rclcpp::QoS RecorderImpl::subscription_qos_for_topic(const std::string & topic_name) const
{
  if (topic_qos_profile_overrides_.count(topic_name)) {
    RCLCPP_INFO_STREAM(
      node->get_logger(),
      "Overriding subscription profile for " << topic_name);
    return topic_qos_profile_overrides_.at(topic_name);
  }
  return rosbag2_storage::Rosbag2QoS::adapt_request_to_offers(
    topic_name, node->get_publishers_info_by_topic(topic_name));
}

void RecorderImpl::warn_if_new_qos_for_subscribed_topic(const std::string & topic_name)
{
  auto existing_subscription = subscriptions_.find(topic_name);
  if (existing_subscription == subscriptions_.end()) {
    // Not subscribed yet
    return;
  }
  if (topics_warned_about_incompatibility_.count(topic_name) > 0) {
    // Already warned about this topic
    return;
  }
  const auto actual_qos = existing_subscription->second->get_actual_qos();
  const auto & used_profile = actual_qos.get_rmw_qos_profile();
  auto publishers_info = node->get_publishers_info_by_topic(topic_name);
  for (const auto & info : publishers_info) {
    auto new_profile = info.qos_profile().get_rmw_qos_profile();
    bool incompatible_reliability =
      new_profile.reliability == RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT &&
      used_profile.reliability != RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
    bool incompatible_durability =
      new_profile.durability == RMW_QOS_POLICY_DURABILITY_VOLATILE &&
      used_profile.durability != RMW_QOS_POLICY_DURABILITY_VOLATILE;

    if (incompatible_reliability) {
      RCLCPP_WARN_STREAM(
        node->get_logger(),
        "A new publisher for subscribed topic " << topic_name << " "
          "was found offering RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT, "
          "but rosbag already subscribed requesting RMW_QOS_POLICY_RELIABILITY_RELIABLE. "
          "Messages from this new publisher will not be recorded.");
      topics_warned_about_incompatibility_.insert(topic_name);
    } else if (incompatible_durability) {
      RCLCPP_WARN_STREAM(
        node->get_logger(),
        "A new publisher for subscribed topic " << topic_name << " "
          "was found offering RMW_QOS_POLICY_DURABILITY_VOLATILE, "
          "but rosbag2 already subscribed requesting RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL. "
          "Messages from this new publisher will not be recorded.");
      topics_warned_about_incompatibility_.insert(topic_name);
    }
  }
}

}  // namespace hector_recorder

