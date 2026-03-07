#include "hector_recorder/recorder_node.hpp"
#include "hector_recorder/utils.h"
#include <chrono>

using namespace std::chrono_literals;
using namespace hector_recorder;

RecorderNode::RecorderNode( const CustomOptions &custom_options,
                            const rosbag2_storage::StorageOptions &storage_options,
                            const rosbag2_transport::RecordOptions &record_options,
                            bool auto_start )
    : Node( custom_options.node_name ), custom_options_( custom_options ),
      storage_options_( storage_options ), record_options_( record_options ),
      raw_output_uri_( storage_options.uri )
{
  // Always publish status
  status_pub_ = this->create_publisher<hector_recorder_msgs::msg::RecorderStatus>(
      "~/recorder_status", 10 );
  status_timer_ = this->create_wall_timer( 1s, [this]() { this->publishStatus(); } );

  // Create services under node namespace
  start_srv_ = this->create_service<hector_recorder_msgs::srv::StartRecording>(
      "~/start_recording",
      std::bind( &RecorderNode::onStartRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  stop_srv_ = this->create_service<hector_recorder_msgs::srv::StopRecording>(
      "~/stop_recording",
      std::bind( &RecorderNode::onStopRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  pause_srv_ = this->create_service<hector_recorder_msgs::srv::PauseRecording>(
      "~/pause_recording",
      std::bind( &RecorderNode::onPauseRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  resume_srv_ = this->create_service<hector_recorder_msgs::srv::ResumeRecording>(
      "~/resume_recording",
      std::bind( &RecorderNode::onResumeRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  split_srv_ = this->create_service<hector_recorder_msgs::srv::SplitBag>(
      "~/split_bag",
      std::bind( &RecorderNode::onSplitBag, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  config_srv_ = this->create_service<hector_recorder_msgs::srv::ApplyConfig>(
      "~/apply_config",
      std::bind( &RecorderNode::onApplyConfig, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  save_config_srv_ = this->create_service<hector_recorder_msgs::srv::SaveConfig>(
      "~/save_config",
      std::bind( &RecorderNode::onSaveConfig, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  topics_srv_ = this->create_service<hector_recorder_msgs::srv::GetAvailableTopics>(
      "~/get_available_topics",
      std::bind( &RecorderNode::onGetAvailableTopics, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  services_srv_ = this->create_service<hector_recorder_msgs::srv::GetAvailableServices>(
      "~/get_available_services",
      std::bind( &RecorderNode::onGetAvailableServices, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  get_config_srv_ = this->create_service<hector_recorder_msgs::srv::GetConfig>(
      "~/get_config",
      std::bind( &RecorderNode::onGetConfig, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  get_info_srv_ = this->create_service<hector_recorder_msgs::srv::GetRecorderInfo>(
      "~/get_recorder_info",
      std::bind( &RecorderNode::onGetRecorderInfo, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  list_bags_srv_ = this->create_service<hector_recorder_msgs::srv::ListBags>(
      "~/list_bags",
      std::bind( &RecorderNode::onListBags, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  get_bag_details_srv_ = this->create_service<hector_recorder_msgs::srv::GetBagDetails>(
      "~/get_bag_details",
      std::bind( &RecorderNode::onGetBagDetails, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  delete_bag_srv_ = this->create_service<hector_recorder_msgs::srv::DeleteBag>(
      "~/delete_bag",
      std::bind( &RecorderNode::onDeleteBag, this, std::placeholders::_1,
                 std::placeholders::_2 ) );

  RCLCPP_INFO( this->get_logger(), "Headless recorder node ready. Waiting for commands..." );

  if ( auto_start ) {
    storage_options_.uri = resolveOutputDirectory( storage_options_.uri );
    initializeRecorder();
    recorder_->record();
    RCLCPP_INFO( this->get_logger(), "Auto-started recording to %s", storage_options_.uri.c_str() );
  }
}

RecorderNode::~RecorderNode()
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  if ( recorder_ && recorder_->is_recording() ) {
    recorder_->stop();
  }
}

void RecorderNode::initializeRecorder()
{
  auto writer_impl = std::make_unique<rosbag2_cpp::writers::SequentialWriter>();
  auto writer = std::make_shared<rosbag2_cpp::Writer>( std::move( writer_impl ) );
  recorder_ = std::make_unique<RecorderImpl>( this, writer, storage_options_, record_options_,
                                              custom_options_.topic_throttle );
}

void RecorderNode::publishStatus()
{
  hector_recorder_msgs::msg::RecorderStatus status_msg;
  {
    std::lock_guard<std::mutex> lock( data_mutex_ );
    fillRecorderStatus( status_msg, recorder_.get(), custom_options_, storage_options_, this );
  }
  status_pub_->publish( status_msg );
}

void RecorderNode::onStartRecording(
    const std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleStartRecording( recorder_, storage_options_, record_options_, custom_options_,
                        raw_output_uri_, request->output_dir, this, response->success,
                        response->message, response->bag_path );
}

void RecorderNode::onStopRecording(
    const std::shared_ptr<hector_recorder_msgs::srv::StopRecording::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::StopRecording::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleStopRecording( recorder_, storage_options_, response->success, response->message,
                       response->bag_path );
  if ( response->success ) {
    RCLCPP_INFO( this->get_logger(), "Recording stopped." );
  }
}

void RecorderNode::onPauseRecording(
    const std::shared_ptr<hector_recorder_msgs::srv::PauseRecording::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::PauseRecording::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  if ( !recorder_ || !recorder_->is_recording() ) {
    response->success = false;
    response->message = "Not currently recording.";
    return;
  }
  recorder_->pause();
  response->success = true;
  response->message = "Recording paused.";
}

void RecorderNode::onResumeRecording(
    const std::shared_ptr<hector_recorder_msgs::srv::ResumeRecording::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::ResumeRecording::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  if ( !recorder_ || !recorder_->is_recording() ) {
    response->success = false;
    response->message = "Not currently recording.";
    return;
  }
  recorder_->resume();
  response->success = true;
  response->message = "Recording resumed.";
}

void RecorderNode::onSplitBag(
    const std::shared_ptr<hector_recorder_msgs::srv::SplitBag::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::SplitBag::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  if ( !recorder_ || !recorder_->is_recording() ) {
    response->success = false;
    response->message = "Not currently recording.";
    return;
  }
  try {
    recorder_->split();
    response->success = true;
    response->message = "Bag file split.";
  } catch ( const std::exception &e ) {
    response->success = false;
    response->message = std::string( "Failed to split bag: " ) + e.what();
  }
}

void RecorderNode::onApplyConfig(
    const std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleApplyConfig( recorder_, custom_options_, record_options_, storage_options_,
                     raw_output_uri_, request->config_yaml, request->restart, this,
                     response->success, response->message, response->active_config_yaml );
}

void RecorderNode::onSaveConfig(
    const std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Response> response )
{
  handleSaveConfig( request->config_yaml, request->file_path, response->success,
                    response->message );
  if ( response->success ) {
    RCLCPP_INFO( this->get_logger(), "Config saved to %s", request->file_path.c_str() );
  }
}

void RecorderNode::onGetAvailableTopics(
    const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Response> response )
{
  handleGetAvailableTopics( this, response->topics, response->types );
}

void RecorderNode::onGetAvailableServices(
    const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableServices::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetAvailableServices::Response> response )
{
  handleGetAvailableServices( this, response->services, response->types );
}

void RecorderNode::onGetConfig(
    const std::shared_ptr<hector_recorder_msgs::srv::GetConfig::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetConfig::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleGetConfig( custom_options_, record_options_, storage_options_, raw_output_uri_,
                   response->config_yaml );
}

void RecorderNode::onGetRecorderInfo(
    const std::shared_ptr<hector_recorder_msgs::srv::GetRecorderInfo::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetRecorderInfo::Response> response )
{
  handleGetRecorderInfo( custom_options_, response->hostname, response->recorded_by,
                         response->config_path );
}

void RecorderNode::onListBags(
    const std::shared_ptr<hector_recorder_msgs::srv::ListBags::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::ListBags::Response> response )
{
  std::string path = request->path;
  if ( path.empty() ) {
    std::lock_guard<std::mutex> lock( data_mutex_ );
    // Use the base output directory (unresolved, i.e. the parent where bags are created)
    path = raw_output_uri_;
  }
  handleListBags( path, storage_options_, response->bags, response->success, response->message );
}

void RecorderNode::onGetBagDetails(
    const std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Response> response )
{
  handleGetBagDetails( request->bag_path, response->info, response->topics, response->success,
                       response->message );
}

void RecorderNode::onDeleteBag(
    const std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Response> response )
{
  handleDeleteBag( request->bag_path, request->confirm, response->success, response->message );
  if ( response->success ) {
    RCLCPP_INFO( this->get_logger(), "Deleted bag: %s", request->bag_path.c_str() );
  }
}
