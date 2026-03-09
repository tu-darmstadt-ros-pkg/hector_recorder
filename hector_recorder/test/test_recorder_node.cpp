#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <rtest/publisher_mock.hpp>
#include <rtest/service_mock.hpp>
#include <rtest/create_timer_mock.hpp>

#include <hector_recorder/recorder_node.hpp>

#include <filesystem>
#include <fstream>

using namespace hector_recorder;
namespace fs = std::filesystem;

// =============================================================================
// Test fixture
// =============================================================================

class RecorderNodeTest : public ::testing::Test
{
protected:
  std::shared_ptr<RecorderNode> node_;

  // Mocks
  std::shared_ptr<rtest::PublisherMock<hector_recorder_msgs::msg::RecorderStatus>> status_pub_mock_;

  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::StartRecording>> start_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::StopRecording>> stop_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::PauseRecording>> pause_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::ResumeRecording>> resume_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::SplitBag>> split_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::ApplyConfig>> config_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::SaveConfig>> save_config_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::GetAvailableTopics>>
      topics_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::GetAvailableServices>>
      services_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::GetConfig>> get_config_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::GetRecorderInfo>>
      get_info_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::ListBags>> list_bags_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::GetBagDetails>>
      get_bag_details_srv_mock_;
  std::shared_ptr<rtest::ServiceMock<hector_recorder_msgs::srv::DeleteBag>> delete_bag_srv_mock_;

  // Accessors for private members
  CustomOptions &customOptions() { return node_->custom_options_; }
  rosbag2_storage::StorageOptions &storageOptions() { return node_->storage_options_; }
  rosbag2_transport::RecordOptions &recordOptions() { return node_->record_options_; }
  std::string &rawOutputUri() { return node_->raw_output_uri_; }
  std::unique_ptr<RecorderImpl> &recorder() { return node_->recorder_; }

  void SetUp() override
  {
    CustomOptions custom_opts;
    custom_opts.node_name = "test_recorder";
    custom_opts.config_path = "";
    custom_opts.publish_status = true;
    custom_opts.recorded_by = "test_user@test_host";

    rosbag2_storage::StorageOptions storage_opts;
    storage_opts.uri = "/tmp/test_bags/";

    rosbag2_transport::RecordOptions record_opts;
    record_opts.all_topics = true;

    // Create node without auto-start (no RecorderImpl, stays in idle state)
    node_ = std::make_shared<RecorderNode>( custom_opts, storage_opts, record_opts, false );

    // Find mocks for all ROS interfaces created by the node
    status_pub_mock_ = rtest::findPublisher<hector_recorder_msgs::msg::RecorderStatus>(
        node_, "/test_recorder/recorder_status" );

    start_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::StartRecording>(
        node_, "~/start_recording" );
    stop_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::StopRecording>(
        node_, "~/stop_recording" );
    pause_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::PauseRecording>(
        node_, "~/pause_recording" );
    resume_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::ResumeRecording>(
        node_, "~/resume_recording" );
    split_srv_mock_ =
        rtest::findService<hector_recorder_msgs::srv::SplitBag>( node_, "~/split_bag" );
    config_srv_mock_ =
        rtest::findService<hector_recorder_msgs::srv::ApplyConfig>( node_, "~/apply_config" );
    save_config_srv_mock_ =
        rtest::findService<hector_recorder_msgs::srv::SaveConfig>( node_, "~/save_config" );
    topics_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::GetAvailableTopics>(
        node_, "~/get_available_topics" );
    services_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::GetAvailableServices>(
        node_, "~/get_available_services" );
    get_config_srv_mock_ =
        rtest::findService<hector_recorder_msgs::srv::GetConfig>( node_, "~/get_config" );
    get_info_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::GetRecorderInfo>(
        node_, "~/get_recorder_info" );
    list_bags_srv_mock_ =
        rtest::findService<hector_recorder_msgs::srv::ListBags>( node_, "~/list_bags" );
    get_bag_details_srv_mock_ = rtest::findService<hector_recorder_msgs::srv::GetBagDetails>(
        node_, "~/get_bag_details" );
    delete_bag_srv_mock_ =
        rtest::findService<hector_recorder_msgs::srv::DeleteBag>( node_, "~/delete_bag" );
  }

  void TearDown() override
  {
    start_srv_mock_.reset();
    stop_srv_mock_.reset();
    pause_srv_mock_.reset();
    resume_srv_mock_.reset();
    split_srv_mock_.reset();
    config_srv_mock_.reset();
    save_config_srv_mock_.reset();
    topics_srv_mock_.reset();
    services_srv_mock_.reset();
    get_config_srv_mock_.reset();
    get_info_srv_mock_.reset();
    list_bags_srv_mock_.reset();
    get_bag_details_srv_mock_.reset();
    delete_bag_srv_mock_.reset();
    status_pub_mock_.reset();
    node_.reset();
    rtest::StaticMocksRegistry::instance().reset();
  }

  // Helper to invoke a service callback via the mock
  template <typename ServiceT>
  auto callService( std::shared_ptr<rtest::ServiceMock<ServiceT>> &mock,
                    std::shared_ptr<typename ServiceT::Request> request )
      -> std::shared_ptr<typename ServiceT::Response>
  {
    auto header = std::make_shared<rmw_request_id_t>();
    auto response = std::make_shared<typename ServiceT::Response>();

    // Capture the response from handle_request
    // The service mock's handle_request calls the node's callback which fills in
    // the response
    auto req_header = std::make_shared<rmw_request_id_t>();
    auto typed_response = mock->handle_request( req_header, request );
    // handle_request returns void but calls send_response.
    // We need to invoke the callback directly instead.
    return response;
  }

  // Direct callback invocation helper — calls the node's service callback directly
  template <typename ServiceT>
  std::shared_ptr<typename ServiceT::Response>
  invokeCallback( rclcpp::Service<ServiceT> *service,
                  std::shared_ptr<typename ServiceT::Request> request )
  {
    auto header = std::make_shared<rmw_request_id_t>();
    return service->handle_request( header, request );
  }
};

// =============================================================================
// Service Existence Tests — verify all 15 services are registered
// =============================================================================

TEST_F( RecorderNodeTest, AllServicesAreRegistered )
{
  ASSERT_NE( start_srv_mock_, nullptr ) << "start_recording service not found";
  ASSERT_NE( stop_srv_mock_, nullptr ) << "stop_recording service not found";
  ASSERT_NE( pause_srv_mock_, nullptr ) << "pause_recording service not found";
  ASSERT_NE( resume_srv_mock_, nullptr ) << "resume_recording service not found";
  ASSERT_NE( split_srv_mock_, nullptr ) << "split_bag service not found";
  ASSERT_NE( config_srv_mock_, nullptr ) << "apply_config service not found";
  ASSERT_NE( save_config_srv_mock_, nullptr ) << "save_config service not found";
  ASSERT_NE( topics_srv_mock_, nullptr ) << "get_available_topics service not found";
  ASSERT_NE( services_srv_mock_, nullptr ) << "get_available_services service not found";
  ASSERT_NE( get_config_srv_mock_, nullptr ) << "get_config service not found";
  ASSERT_NE( get_info_srv_mock_, nullptr ) << "get_recorder_info service not found";
  ASSERT_NE( list_bags_srv_mock_, nullptr ) << "list_bags service not found";
  ASSERT_NE( get_bag_details_srv_mock_, nullptr ) << "get_bag_details service not found";
  ASSERT_NE( delete_bag_srv_mock_, nullptr ) << "delete_bag service not found";
}

TEST_F( RecorderNodeTest, StatusPublisherIsRegistered )
{
  ASSERT_NE( status_pub_mock_, nullptr ) << "status publisher not found";
}

TEST_F( RecorderNodeTest, TimerIsRegistered )
{
  auto timers = rtest::findTimers( node_ );
  ASSERT_GE( timers.size(), 1u ) << "status timer not found";
}

// =============================================================================
// Idle State Tests — services respond correctly when not recording
// =============================================================================

TEST_F( RecorderNodeTest, StopRecordingWhenIdle_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::StopRecording::Request>();
  EXPECT_CALL( *stop_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::StopRecording::Response &r ) {
        EXPECT_FALSE( r.success );
        EXPECT_FALSE( r.message.empty() );
      } );
  stop_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, PauseRecordingWhenIdle_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::PauseRecording::Request>();
  EXPECT_CALL( *pause_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce(
          []( rmw_request_id_t &, hector_recorder_msgs::srv::PauseRecording::Response &r ) {
            EXPECT_FALSE( r.success );
            EXPECT_EQ( r.message, "Not currently recording." );
          } );
  pause_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, ResumeRecordingWhenIdle_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::ResumeRecording::Request>();
  EXPECT_CALL( *resume_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce(
          []( rmw_request_id_t &, hector_recorder_msgs::srv::ResumeRecording::Response &r ) {
            EXPECT_FALSE( r.success );
            EXPECT_EQ( r.message, "Not currently recording." );
          } );
  resume_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, SplitBagWhenIdle_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::SplitBag::Request>();
  EXPECT_CALL( *split_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::SplitBag::Response &r ) {
        EXPECT_FALSE( r.success );
        EXPECT_EQ( r.message, "Not currently recording." );
      } );
  split_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

// =============================================================================
// GetRecorderInfo Tests
// =============================================================================

TEST_F( RecorderNodeTest, GetRecorderInfo_ReturnsConfiguredValues )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::GetRecorderInfo::Request>();
  EXPECT_CALL( *get_info_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce(
          []( rmw_request_id_t &, hector_recorder_msgs::srv::GetRecorderInfo::Response &r ) {
            EXPECT_EQ( r.recorded_by, "test_user@test_host" );
            EXPECT_FALSE( r.hostname.empty() );
          } );
  get_info_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

// =============================================================================
// GetConfig Tests
// =============================================================================

TEST_F( RecorderNodeTest, GetConfig_ReturnsValidYaml )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::GetConfig::Request>();
  EXPECT_CALL( *get_config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::GetConfig::Response &r ) {
        EXPECT_FALSE( r.config_yaml.empty() );
        // Should contain the output path
        EXPECT_NE( r.config_yaml.find( "/tmp/test_bags/" ), std::string::npos );
      } );
  get_config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, GetConfig_ContainsAllTopics )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::GetConfig::Request>();
  EXPECT_CALL( *get_config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::GetConfig::Response &r ) {
        // all_topics should be true in the config since we set it
        EXPECT_NE( r.config_yaml.find( "all_topics: true" ), std::string::npos );
      } );
  get_config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

// =============================================================================
// ApplyConfig Tests
// =============================================================================

TEST_F( RecorderNodeTest, ApplyConfig_ValidYaml_Succeeds )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::ApplyConfig::Request>();
  request->config_yaml = "output: /tmp/new_output/\nall_topics: false\ntopics:\n  - /tf\n";
  request->restart = false;

  EXPECT_CALL( *config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::ApplyConfig::Response &r ) {
        EXPECT_TRUE( r.success );
        EXPECT_FALSE( r.active_config_yaml.empty() );
      } );
  config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, ApplyConfig_InvalidYaml_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::ApplyConfig::Request>();
  request->config_yaml = ":\n  :\n    - [\n";
  request->restart = false;

  EXPECT_CALL( *config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::ApplyConfig::Response &r ) {
        EXPECT_FALSE( r.success );
      } );
  config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, ApplyConfig_UpdatesInternalState )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::ApplyConfig::Request>();
  request->config_yaml = "output: /tmp/changed_output/\nall_topics: false\ntopics:\n  - /cmd_vel\n";
  request->restart = false;

  EXPECT_CALL( *config_srv_mock_, send_response( ::testing::_, ::testing::_ ) ).Times( 1 );
  config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );

  // Verify internal state was updated
  EXPECT_FALSE( recordOptions().all_topics );
  ASSERT_EQ( recordOptions().topics.size(), 1u );
  EXPECT_EQ( recordOptions().topics[0], "/cmd_vel" );
}

// =============================================================================
// Config Round-Trip Test
// =============================================================================

TEST_F( RecorderNodeTest, ConfigRoundTrip_Idempotent )
{
  // Apply a known config, then get → apply → get and verify idempotency.
  // The first apply normalizes defaults (e.g. empty rmw_serialization_format → "cdr"),
  // so we test that a second round-trip is stable.

  std::string known_yaml =
      "output: /tmp/roundtrip/\nall_topics: false\ntopics:\n  - /tf\n  - /odom\n";

  // Apply known config
  {
    auto request = std::make_shared<hector_recorder_msgs::srv::ApplyConfig::Request>();
    request->config_yaml = known_yaml;
    request->restart = false;
    EXPECT_CALL( *config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
        .WillOnce(
            []( rmw_request_id_t &, hector_recorder_msgs::srv::ApplyConfig::Response &r ) {
              EXPECT_TRUE( r.success );
            } );
    config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
  }

  // Get normalized config (first round)
  std::string normalized_yaml;
  {
    auto request = std::make_shared<hector_recorder_msgs::srv::GetConfig::Request>();
    EXPECT_CALL( *get_config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
        .WillOnce( [&normalized_yaml]( rmw_request_id_t &,
                                       hector_recorder_msgs::srv::GetConfig::Response &r ) {
          normalized_yaml = r.config_yaml;
        } );
    get_config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
  }
  ASSERT_FALSE( normalized_yaml.empty() );
  // Verify applied topics are present
  EXPECT_NE( normalized_yaml.find( "/tf" ), std::string::npos );
  EXPECT_NE( normalized_yaml.find( "/odom" ), std::string::npos );
  EXPECT_NE( normalized_yaml.find( "/tmp/roundtrip/" ), std::string::npos );

  // Re-find mocks (consumed after first use)
  config_srv_mock_.reset();
  config_srv_mock_ =
      rtest::findService<hector_recorder_msgs::srv::ApplyConfig>( node_, "~/apply_config" );
  get_config_srv_mock_.reset();
  get_config_srv_mock_ =
      rtest::findService<hector_recorder_msgs::srv::GetConfig>( node_, "~/get_config" );

  // Apply the normalized config back
  {
    auto request = std::make_shared<hector_recorder_msgs::srv::ApplyConfig::Request>();
    request->config_yaml = normalized_yaml;
    request->restart = false;
    EXPECT_CALL( *config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
        .WillOnce(
            []( rmw_request_id_t &, hector_recorder_msgs::srv::ApplyConfig::Response &r ) {
              EXPECT_TRUE( r.success );
            } );
    config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
  }

  // Get config again — should be identical to the normalized version
  {
    auto request = std::make_shared<hector_recorder_msgs::srv::GetConfig::Request>();
    EXPECT_CALL( *get_config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
        .WillOnce( [&normalized_yaml]( rmw_request_id_t &,
                                       hector_recorder_msgs::srv::GetConfig::Response &r ) {
          EXPECT_EQ( r.config_yaml, normalized_yaml );
        } );
    get_config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
  }
}

// =============================================================================
// SaveConfig Tests
// =============================================================================

TEST_F( RecorderNodeTest, SaveConfig_WritesFile )
{
  std::string tmp_path = "/tmp/rtest_save_config_test.yaml";
  // Cleanup beforehand
  fs::remove( tmp_path );

  auto request = std::make_shared<hector_recorder_msgs::srv::SaveConfig::Request>();
  request->config_yaml = "output: /tmp/test/\nall_topics: true\n";
  request->file_path = tmp_path;

  EXPECT_CALL( *save_config_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::SaveConfig::Response &r ) {
        EXPECT_TRUE( r.success );
      } );
  save_config_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );

  // Verify file was written
  ASSERT_TRUE( fs::exists( tmp_path ) );
  std::ifstream ifs( tmp_path );
  std::string content( ( std::istreambuf_iterator<char>( ifs ) ),
                       std::istreambuf_iterator<char>() );
  EXPECT_EQ( content, request->config_yaml );

  fs::remove( tmp_path );
}

// =============================================================================
// Status Publishing Tests
// =============================================================================

TEST_F( RecorderNodeTest, StatusPublish_IdleState )
{
  EXPECT_CALL( *status_pub_mock_,
               publish( ::testing::_ ) )
      .WillOnce( []( const hector_recorder_msgs::msg::RecorderStatus &msg ) {
        EXPECT_EQ( msg.state, hector_recorder_msgs::msg::RecorderStatus::IDLE );
        EXPECT_EQ( msg.node_name, "/test_recorder" );
      } );

  // Trigger the timer callback
  auto timers = rtest::findTimers( node_ );
  ASSERT_GE( timers.size(), 1u );
  timers[0]->execute_callback( std::make_shared<int>( 0 ) );
}

// =============================================================================
// DeleteBag Tests
// =============================================================================

TEST_F( RecorderNodeTest, DeleteBag_WithoutConfirm_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::DeleteBag::Request>();
  request->bag_path = "/tmp/some_bag";
  request->confirm = false;

  EXPECT_CALL( *delete_bag_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::DeleteBag::Response &r ) {
        EXPECT_FALSE( r.success );
      } );
  delete_bag_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

// =============================================================================
// ListBags Tests
// =============================================================================

TEST_F( RecorderNodeTest, ListBags_InvalidPath_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::ListBags::Request>();
  request->path = "/nonexistent/path/that/does/not/exist";

  EXPECT_CALL( *list_bags_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::ListBags::Response &r ) {
        EXPECT_FALSE( r.success );
      } );
  list_bags_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

TEST_F( RecorderNodeTest, ListBags_EmptyPath_UsesRawOutputUri )
{
  // Set raw_output_uri to a path that doesn't exist
  rawOutputUri() = "/tmp/rtest_nonexistent_bag_dir";

  auto request = std::make_shared<hector_recorder_msgs::srv::ListBags::Request>();
  request->path = ""; // Empty path → should use raw_output_uri_

  EXPECT_CALL( *list_bags_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce( []( rmw_request_id_t &, hector_recorder_msgs::srv::ListBags::Response &r ) {
        // Path doesn't exist, so it should fail
        EXPECT_FALSE( r.success );
      } );
  list_bags_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

// =============================================================================
// GetBagDetails Tests
// =============================================================================

TEST_F( RecorderNodeTest, GetBagDetails_InvalidPath_Fails )
{
  auto request = std::make_shared<hector_recorder_msgs::srv::GetBagDetails::Request>();
  request->bag_path = "/nonexistent/bag/path";

  EXPECT_CALL( *get_bag_details_srv_mock_, send_response( ::testing::_, ::testing::_ ) )
      .WillOnce(
          []( rmw_request_id_t &, hector_recorder_msgs::srv::GetBagDetails::Response &r ) {
            EXPECT_FALSE( r.success );
          } );
  get_bag_details_srv_mock_->handle_request( std::make_shared<rmw_request_id_t>(), request );
}

int main( int argc, char **argv )
{
  testing::InitGoogleMock( &argc, argv );
  rclcpp::init( argc, argv );
  int result = RUN_ALL_TESTS();
  rclcpp::shutdown();
  return result;
}
