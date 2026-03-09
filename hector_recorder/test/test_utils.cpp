#include <gtest/gtest.h>
#include <filesystem>
#include <fstream>

#include "hector_recorder/config_yaml.h"
#include "hector_recorder/service_handlers.h"

namespace fs = std::filesystem;
using namespace hector_recorder;

// ========================================================================
// Test fixture with a temporary directory
// ========================================================================

class UtilsTest : public ::testing::Test
{
protected:
  fs::path tmp_dir_;

  void SetUp() override
  {
    tmp_dir_ = fs::temp_directory_path() / ( "hector_recorder_test_" + std::to_string( getpid() ) );
    fs::create_directories( tmp_dir_ );
  }

  void TearDown() override
  {
    std::error_code ec;
    fs::remove_all( tmp_dir_, ec );
  }

  /// Create a fake rosbag directory with a metadata.yaml
  fs::path createFakeBag( const std::string &name,
                          const std::string &recorded_by = "" )
  {
    fs::path bag = tmp_dir_ / name;
    fs::create_directories( bag );

    // Write a minimal metadata.yaml compatible with rosbag2 MetadataIo (version 9)
    std::ofstream ofs( ( bag / "metadata.yaml" ).string() );
    ofs << "rosbag2_bagfile_information:\n"
        << "  version: 9\n"
        << "  storage_identifier: sqlite3\n"
        << "  duration:\n"
        << "    nanoseconds: 5000000000\n"
        << "  starting_time:\n"
        << "    nanoseconds_since_epoch: 1709827200000000000\n"
        << "  message_count: 42\n"
        << "  topics_with_message_count:\n"
        << "    - topic_metadata:\n"
        << "        name: /test_topic\n"
        << "        type: std_msgs/msg/String\n"
        << "        serialization_format: cdr\n"
        << "        offered_qos_profiles:\n"
        << "          []\n"
        << "        type_description_hash: \"\"\n"
        << "      message_count: 42\n"
        << "  compression_format: \"\"\n"
        << "  compression_mode: \"\"\n"
        << "  relative_file_paths:\n"
        << "    - " << name << "_0.db3\n"
        << "  files:\n"
        << "    - path: " << name << "_0.db3\n"
        << "      starting_time:\n"
        << "        nanoseconds_since_epoch: 0\n"
        << "      duration:\n"
        << "        nanoseconds: 0\n"
        << "      message_count: 0\n"
        << "  ros_distro: jazzy\n";

    if ( !recorded_by.empty() ) {
      ofs << "  custom_data:\n"
          << "    recorded_by: " << recorded_by << "\n";
    } else {
      ofs << "  custom_data: ~\n";
    }

    ofs.close();

    // Create a dummy db3 file so directorySize returns > 0
    std::ofstream db( ( bag / ( name + "_0.db3" ) ).string() );
    db << "fake data for size testing";
    db.close();

    return bag;
  }
};

// ========================================================================
// resolveOutputDirectory tests
// ========================================================================

TEST_F( UtilsTest, ResolveEmptyPath_UsesCwdWithTimestamp )
{
  std::string result = resolveOutputDirectory( "" );
  // Should be under CWD with rosbag2_ prefix
  EXPECT_TRUE( result.find( "rosbag2_" ) != std::string::npos );
}

TEST_F( UtilsTest, ResolveTrailingSlash_AppendsTimestamp )
{
  std::string input = tmp_dir_.string() + "/";
  std::string result = resolveOutputDirectory( input );

  // Should be tmp_dir/rosbag2_<timestamp>
  EXPECT_TRUE( fs::path( result ).parent_path() == tmp_dir_ );
  EXPECT_TRUE( fs::path( result ).filename().string().find( "rosbag2_" ) == 0 );
}

TEST_F( UtilsTest, ResolveExactName_UsesAsIs )
{
  // Non-existing path without trailing slash → use as bag dir name
  std::string input = ( tmp_dir_ / "my_experiment" ).string();
  std::string result = resolveOutputDirectory( input );

  EXPECT_EQ( result, input );
}

TEST_F( UtilsTest, ResolveExistingDir_AppendsTimestamp )
{
  // Create an existing (non-rosbag) directory
  fs::path subdir = tmp_dir_ / "existing_dir";
  fs::create_directories( subdir );

  std::string result = resolveOutputDirectory( subdir.string() );

  // Should be existing_dir/rosbag2_<timestamp>
  EXPECT_TRUE( fs::path( result ).parent_path() == subdir );
  EXPECT_TRUE( fs::path( result ).filename().string().find( "rosbag2_" ) == 0 );
}

TEST_F( UtilsTest, ResolveExistingRosbagDir_CreatesSiblingTimestamp )
{
  // Create an existing rosbag directory (has metadata.yaml)
  createFakeBag( "old_bag" );

  std::string result = resolveOutputDirectory( ( tmp_dir_ / "old_bag" ).string() );

  // Should create a sibling in the parent dir, not inside old_bag
  EXPECT_TRUE( fs::path( result ).parent_path() == tmp_dir_ );
  EXPECT_TRUE( fs::path( result ).filename().string().find( "rosbag2_" ) == 0 );
}

TEST_F( UtilsTest, ResolveExistingFile_Throws )
{
  // Create a regular file
  fs::path file = tmp_dir_ / "not_a_dir";
  std::ofstream( file.string() ) << "data";

  EXPECT_THROW( resolveOutputDirectory( file.string() ), std::runtime_error );
}

TEST_F( UtilsTest, ResolveExistingNonBagDir_NoTrailingSlash_AppendsTimestamp )
{
  // An existing non-rosbag directory without trailing slash is treated like
  // a container: a timestamped subdirectory is created inside it.
  fs::path target = tmp_dir_ / "my_dir";
  fs::create_directories( target );

  std::string result = resolveOutputDirectory( target.string() );

  EXPECT_TRUE( fs::path( result ).parent_path() == target );
  EXPECT_TRUE( fs::path( result ).filename().string().find( "rosbag2_" ) == 0 );
}

TEST_F( UtilsTest, ResolveInsideRosbag_Throws )
{
  // Create a rosbag and try to place a new one inside it
  auto bag = createFakeBag( "parent_bag" );
  std::string nested = ( bag / "nested/" ).string();

  EXPECT_THROW( resolveOutputDirectory( nested ), std::runtime_error );
}

TEST_F( UtilsTest, ResolveTilde_ExpandsHome )
{
  const char *home = std::getenv( "HOME" );
  if ( !home )
    GTEST_SKIP() << "HOME not set";

  std::string result = resolveOutputDirectory( "~/hector_test_resolve_tilde/" );

  // Should start with $HOME
  EXPECT_TRUE( result.find( home ) == 0 );
  EXPECT_TRUE( result.find( "rosbag2_" ) != std::string::npos );

  // Clean up the created parent
  std::error_code ec;
  fs::remove_all( std::string( home ) + "/hector_test_resolve_tilde", ec );
}

TEST_F( UtilsTest, ResolveEnvVar_Expands )
{
  setenv( "HECTOR_TEST_DIR", tmp_dir_.c_str(), 1 );
  std::string result = resolveOutputDirectory( "$HECTOR_TEST_DIR/" );

  EXPECT_TRUE( fs::path( result ).parent_path() == tmp_dir_ );
  EXPECT_TRUE( fs::path( result ).filename().string().find( "rosbag2_" ) == 0 );
  unsetenv( "HECTOR_TEST_DIR" );
}

TEST_F( UtilsTest, ResolveEnvVarBraces_Expands )
{
  setenv( "HECTOR_TEST_DIR2", tmp_dir_.c_str(), 1 );
  std::string result = resolveOutputDirectory( "${HECTOR_TEST_DIR2}/" );

  EXPECT_TRUE( fs::path( result ).parent_path() == tmp_dir_ );
  unsetenv( "HECTOR_TEST_DIR2" );
}

TEST_F( UtilsTest, ResolveCreatesParentDirs )
{
  fs::path deep = tmp_dir_ / "a" / "b" / "c" / "my_bag";
  std::string result = resolveOutputDirectory( deep.string() );

  EXPECT_EQ( result, deep.string() );
  // Parent dirs should have been created
  EXPECT_TRUE( fs::is_directory( deep.parent_path() ) );
}

// ========================================================================
// YAML config parse/serialize round-trip tests
// ========================================================================

class YamlConfigTest : public ::testing::Test
{
protected:
  CustomOptions custom_;
  rosbag2_transport::RecordOptions record_;
  rosbag2_storage::StorageOptions storage_;

  void SetUp() override
  {
    custom_ = {};
    record_ = {};
    storage_ = {};
  }
};

TEST_F( YamlConfigTest, ParseBasicConfig )
{
  std::string yaml = R"(
node_name: "test_recorder"
output: "~/bags/"
storage_id: "mcap"
all_topics: true
publish_status: true
rmw_serialization_format: "cdr"
)";

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );

  EXPECT_EQ( custom_.node_name, "test_recorder" );
  EXPECT_EQ( storage_.uri, "~/bags/" );
  EXPECT_EQ( storage_.storage_id, "mcap" );
  EXPECT_TRUE( record_.all_topics );
  EXPECT_TRUE( custom_.publish_status );
  EXPECT_EQ( record_.rmw_serialization_format, "cdr" );
}

TEST_F( YamlConfigTest, ParseTopicList )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
all_topics: false
topics:
  - "/camera/image_raw"
  - "/imu/data"
  - "/odom"
)";

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );

  EXPECT_FALSE( record_.all_topics );
  ASSERT_EQ( record_.topics.size(), 3u );
  EXPECT_EQ( record_.topics[0], "/camera/image_raw" );
  EXPECT_EQ( record_.topics[1], "/imu/data" );
  EXPECT_EQ( record_.topics[2], "/odom" );
}

TEST_F( YamlConfigTest, ParseThrottleMessages )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
topic_throttle:
  "/camera/image_raw":
    type: "messages"
    msgs_per_sec: 5.0
)";

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );

  ASSERT_EQ( custom_.topic_throttle.size(), 1u );
  auto it = custom_.topic_throttle.find( "/camera/image_raw" );
  ASSERT_NE( it, custom_.topic_throttle.end() );
  EXPECT_EQ( it->second.type, ThrottleConfig::MESSAGES );
  EXPECT_DOUBLE_EQ( it->second.msgs_per_sec, 5.0 );
}

TEST_F( YamlConfigTest, ParseThrottleBytes )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
topic_throttle:
  "/lidar/points":
    type: "bytes"
    bytes_per_sec: 500000
    window: 2.0
)";

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );

  auto it = custom_.topic_throttle.find( "/lidar/points" );
  ASSERT_NE( it, custom_.topic_throttle.end() );
  EXPECT_EQ( it->second.type, ThrottleConfig::BYTES );
  EXPECT_EQ( it->second.bytes_per_sec, 500000 );
  EXPECT_DOUBLE_EQ( it->second.window, 2.0 );
}

TEST_F( YamlConfigTest, ParseThrottleMissingRate_Throws )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
topic_throttle:
  "/topic":
    type: "messages"
)";

  EXPECT_FALSE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );
}

TEST_F( YamlConfigTest, ParseStorageOptions )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
storage_id: "mcap"
max_bag_size_gb: 2.5
max_bag_duration: 300
max_cache_size: 1000000
snapshot_mode: true
)";

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );

  EXPECT_EQ( storage_.storage_id, "mcap" );
  // 2.5 GB in bytes
  EXPECT_GT( storage_.max_bagfile_size, 2000000000ull );
  EXPECT_LT( storage_.max_bagfile_size, 3000000000ull );
  EXPECT_EQ( storage_.max_bagfile_duration, 300u );
  EXPECT_EQ( storage_.max_cache_size, 1000000u );
  EXPECT_TRUE( storage_.snapshot_mode );
}

TEST_F( YamlConfigTest, ParseConflictingMaxBagSize_Throws )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
max_bag_size: 1000
max_bag_size_gb: 1.0
)";

  EXPECT_FALSE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );
}

TEST_F( YamlConfigTest, ParseRecordOptions )
{
  std::string yaml = R"(
node_name: "rec"
output: "/tmp/"
all_topics: true
all_services: true
include_hidden_topics: true
include_unpublished_topics: true
start_paused: true
exclude_topics:
  - "/rosout"
exclude_topic_types:
  - "rcl_interfaces/msg/Log"
)";

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );

  EXPECT_TRUE( record_.all_topics );
  EXPECT_TRUE( record_.all_services );
  EXPECT_TRUE( record_.include_hidden_topics );
  EXPECT_TRUE( record_.include_unpublished_topics );
  EXPECT_TRUE( record_.start_paused );
  ASSERT_EQ( record_.exclude_topics.size(), 1u );
  EXPECT_EQ( record_.exclude_topics[0], "/rosout" );
  ASSERT_EQ( record_.exclude_topic_types.size(), 1u );
  EXPECT_EQ( record_.exclude_topic_types[0], "rcl_interfaces/msg/Log" );
}

TEST_F( YamlConfigTest, SerializeRoundTrip )
{
  // Set up a config
  custom_.node_name = "my_recorder";
  custom_.publish_status = true;
  custom_.status_topic = "recorder_status";

  storage_.uri = "/tmp/bags/";
  storage_.storage_id = "sqlite3";
  storage_.max_bagfile_size = 1073741824; // 1 GiB

  record_.all_topics = false;
  record_.topics = { "/camera/image_raw", "/imu/data" };
  record_.rmw_serialization_format = "cdr";

  // Add a throttle rule
  ThrottleConfig tc;
  tc.type = ThrottleConfig::MESSAGES;
  tc.msgs_per_sec = 10.0;
  custom_.topic_throttle["/camera/image_raw"] = tc;

  // Serialize
  std::string yaml = serializeConfigToYaml( custom_, record_, storage_, "/original/path/" );

  // Parse back
  CustomOptions custom2;
  rosbag2_transport::RecordOptions record2;
  rosbag2_storage::StorageOptions storage2;

  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom2, record2, storage2 ) );

  // Verify round-trip
  EXPECT_EQ( custom2.node_name, "my_recorder" );
  EXPECT_TRUE( custom2.publish_status );
  EXPECT_EQ( storage2.storage_id, "sqlite3" );
  EXPECT_EQ( storage2.max_bagfile_size, 1073741824u );
  EXPECT_FALSE( record2.all_topics );
  ASSERT_EQ( record2.topics.size(), 2u );
  EXPECT_EQ( record2.topics[0], "/camera/image_raw" );
  EXPECT_EQ( record2.topics[1], "/imu/data" );

  // Throttle should survive round-trip
  ASSERT_EQ( custom2.topic_throttle.size(), 1u );
  auto it = custom2.topic_throttle.find( "/camera/image_raw" );
  ASSERT_NE( it, custom2.topic_throttle.end() );
  EXPECT_EQ( it->second.type, ThrottleConfig::MESSAGES );
  EXPECT_DOUBLE_EQ( it->second.msgs_per_sec, 10.0 );

  // Output override should be used instead of storage_options.uri
  EXPECT_EQ( storage2.uri, "/original/path/" );
}

TEST_F( YamlConfigTest, SerializeRoundTripBytesThrottle )
{
  custom_.node_name = "rec";
  storage_.uri = "/tmp/";
  storage_.storage_id = "sqlite3";

  ThrottleConfig tc;
  tc.type = ThrottleConfig::BYTES;
  tc.bytes_per_sec = 500000;
  tc.window = 2.5;
  custom_.topic_throttle["/lidar/points"] = tc;

  std::string yaml = serializeConfigToYaml( custom_, record_, storage_ );

  CustomOptions custom2;
  rosbag2_transport::RecordOptions record2;
  rosbag2_storage::StorageOptions storage2;
  ASSERT_TRUE( parseYamlConfigFromString( yaml, custom2, record2, storage2 ) );

  auto it = custom2.topic_throttle.find( "/lidar/points" );
  ASSERT_NE( it, custom2.topic_throttle.end() );
  EXPECT_EQ( it->second.type, ThrottleConfig::BYTES );
  EXPECT_EQ( it->second.bytes_per_sec, 500000 );
  EXPECT_DOUBLE_EQ( it->second.window, 2.5 );
}

TEST_F( YamlConfigTest, ParseInvalidYaml_ReturnsFalse )
{
  // Use a string that truly cannot be parsed as YAML
  std::string yaml = ":\n  :\n    - [\n";
  EXPECT_FALSE( parseYamlConfigFromString( yaml, custom_, record_, storage_ ) );
}

// ========================================================================
// Format function tests
// ========================================================================

TEST( FormatTest, FormatMemory )
{
  EXPECT_EQ( formatMemory( 0 ), "0.0 B" );
  EXPECT_EQ( formatMemory( 512 ), "512.0 B" );
  EXPECT_EQ( formatMemory( 1024 ), "1.0 KiB" );
  EXPECT_EQ( formatMemory( 1536 ), "1.5 KiB" );
  EXPECT_EQ( formatMemory( 1048576 ), "1.0 MiB" );
  EXPECT_EQ( formatMemory( 1073741824 ), "1.0 GiB" );
  EXPECT_EQ( formatMemory( 1099511627776ull ), "1.0 TiB" );
}

TEST( FormatTest, RateToString )
{
  EXPECT_EQ( rateToString( 0.0 ), "0.0 Hz" );
  EXPECT_EQ( rateToString( 30.0 ), "30.0 Hz" );
  EXPECT_EQ( rateToString( 999.9 ), "999.9 Hz" );
  EXPECT_EQ( rateToString( 1000.0 ), "1.0 kHz" );
  EXPECT_EQ( rateToString( 1500.0 ), "1.5 kHz" );
  EXPECT_EQ( rateToString( 1000000.0 ), "1.0 MHz" );
}

TEST( FormatTest, BandwidthToString )
{
  EXPECT_EQ( bandwidthToString( 0.0 ), "0.0 B/s" );
  EXPECT_EQ( bandwidthToString( 500.0 ), "500.0 B/s" );
  EXPECT_EQ( bandwidthToString( 1000.0 ), "1.0 kB/s" );
  EXPECT_EQ( bandwidthToString( 1500000.0 ), "1.5 MB/s" );
  EXPECT_EQ( bandwidthToString( 2000000000.0 ), "2.0 GB/s" );
}

// ========================================================================
// String utility tests
// ========================================================================

TEST( StringUtilsTest, ClipString_Short )
{
  EXPECT_EQ( clipString( "/short", 20 ), "/short" );
}

TEST( StringUtilsTest, ClipString_Long )
{
  std::string long_path = "/very/long/path/to/some/deeply/nested/topic_name";
  std::string clipped = clipString( long_path, 30 );
  EXPECT_LE( static_cast<int>( clipped.size() ), 30 );
  EXPECT_TRUE( clipped.find( "..." ) != std::string::npos );
  // Should preserve the last segment
  EXPECT_TRUE( clipped.find( "/topic_name" ) != std::string::npos );
}

TEST( StringUtilsTest, ClipString_NoSlash )
{
  std::string s = "a_very_long_string_without_any_slashes_at_all";
  std::string clipped = clipString( s, 20 );
  EXPECT_LE( static_cast<int>( clipped.size() ), 20 );
  EXPECT_TRUE( clipped.find( "..." ) != std::string::npos );
}

TEST( StringUtilsTest, EnsureLeadingSlash )
{
  std::vector<std::string> topics = { "topic1", "/topic2", "ns/topic3" };
  ensureLeadingSlash( topics );

  EXPECT_EQ( topics[0], "/topic1" );
  EXPECT_EQ( topics[1], "/topic2" );
  EXPECT_EQ( topics[2], "/ns/topic3" );
}

TEST( StringUtilsTest, EnsureLeadingSlash_Empty )
{
  std::vector<std::string> empty;
  ensureLeadingSlash( empty );
  EXPECT_TRUE( empty.empty() );
}

// ========================================================================
// isInfrastructureService tests
// ========================================================================

TEST( InfrastructureServiceTest, ParameterServices )
{
  EXPECT_TRUE( isInfrastructureService( "/node/list_parameters" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/describe_parameters" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_parameters" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/set_parameters" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_parameter_types" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/set_parameters_atomically" ) );
}

TEST( InfrastructureServiceTest, LifecycleServices )
{
  EXPECT_TRUE( isInfrastructureService( "/node/change_state" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_state" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_available_states" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_available_transitions" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_transition_graph" ) );
}

TEST( InfrastructureServiceTest, TypeDescriptionService )
{
  EXPECT_TRUE( isInfrastructureService( "/node/get_type_description" ) );
}

TEST( InfrastructureServiceTest, LoggerServices )
{
  EXPECT_TRUE( isInfrastructureService( "/node/set_logger_levels" ) );
  EXPECT_TRUE( isInfrastructureService( "/node/get_logger_levels" ) );
}

TEST( InfrastructureServiceTest, UserServices_NotFiltered )
{
  EXPECT_FALSE( isInfrastructureService( "/node/start_recording" ) );
  EXPECT_FALSE( isInfrastructureService( "/node/stop_recording" ) );
  EXPECT_FALSE( isInfrastructureService( "/node/get_config" ) );
  EXPECT_FALSE( isInfrastructureService( "/my_custom_service" ) );
}

TEST( InfrastructureServiceTest, NamespacedServices )
{
  EXPECT_TRUE( isInfrastructureService( "/ns1/ns2/node/list_parameters" ) );
  EXPECT_FALSE( isInfrastructureService( "/ns1/ns2/node/my_service" ) );
}

TEST( InfrastructureServiceTest, NoSlash )
{
  // Edge case: no slash at all
  EXPECT_FALSE( isInfrastructureService( "list_parameters" ) );
}

// ========================================================================
// handleGetRecorderInfo tests
// ========================================================================

TEST( RecorderInfoTest, DefaultRecordedBy )
{
  CustomOptions opts;
  opts.config_path = "/path/to/config.yaml";

  std::string hostname, recorded_by, config_path;
  handleGetRecorderInfo( opts, hostname, recorded_by, config_path );

  EXPECT_FALSE( hostname.empty() );
  EXPECT_FALSE( recorded_by.empty() );
  EXPECT_TRUE( recorded_by.find( "@" ) != std::string::npos );
  EXPECT_EQ( config_path, "/path/to/config.yaml" );
}

TEST( RecorderInfoTest, CustomRecordedBy )
{
  CustomOptions opts;
  opts.recorded_by = "alice@robot";
  opts.config_path = "config.yaml";

  std::string hostname, recorded_by, config_path;
  handleGetRecorderInfo( opts, hostname, recorded_by, config_path );

  EXPECT_EQ( recorded_by, "alice@robot" );
}

// ========================================================================
// handleSaveConfig tests
// ========================================================================

class SaveConfigTest : public UtilsTest {};

TEST_F( SaveConfigTest, SaveAndReadBack )
{
  fs::path file = tmp_dir_ / "subdir" / "config.yaml";
  std::string yaml = "node_name: test\noutput: /tmp/\n";
  bool success = false;
  std::string message;

  handleSaveConfig( yaml, file.string(), success, message );

  EXPECT_TRUE( success );
  EXPECT_TRUE( fs::exists( file ) );

  // Read back
  std::ifstream ifs( file.string() );
  std::string content( ( std::istreambuf_iterator<char>( ifs ) ),
                       std::istreambuf_iterator<char>() );
  EXPECT_EQ( content, yaml );
}

TEST_F( SaveConfigTest, SaveToInvalidPath )
{
  // Try to save to a path where parent is a file (not a directory)
  fs::path blocker = tmp_dir_ / "blocker";
  std::ofstream( blocker.string() ) << "data";

  fs::path file = blocker / "config.yaml";
  bool success = true;
  std::string message;

  handleSaveConfig( "yaml", file.string(), success, message );

  EXPECT_FALSE( success );
}

// ========================================================================
// handleDeleteBag tests
// ========================================================================

class DeleteBagTest : public UtilsTest {};

TEST_F( DeleteBagTest, DeleteWithConfirm )
{
  auto bag = createFakeBag( "deleteme" );
  bool success = false;
  std::string message;

  handleDeleteBag( bag.string(), true, success, message );

  EXPECT_TRUE( success );
  EXPECT_FALSE( fs::exists( bag ) );
}

TEST_F( DeleteBagTest, DeleteWithoutConfirm )
{
  auto bag = createFakeBag( "keepme" );
  bool success = true;
  std::string message;

  handleDeleteBag( bag.string(), false, success, message );

  EXPECT_FALSE( success );
  EXPECT_TRUE( fs::exists( bag ) ); // Should still exist
}

TEST_F( DeleteBagTest, DeleteNonBagDir )
{
  fs::path dir = tmp_dir_ / "not_a_bag";
  fs::create_directories( dir );
  bool success = true;
  std::string message;

  handleDeleteBag( dir.string(), true, success, message );

  EXPECT_FALSE( success );
  EXPECT_TRUE( fs::exists( dir ) ); // Should still exist
}

TEST_F( DeleteBagTest, DeleteNonExistent )
{
  bool success = true;
  std::string message;

  handleDeleteBag( ( tmp_dir_ / "ghost" ).string(), true, success, message );

  EXPECT_FALSE( success );
}

// ========================================================================
// handleListBags tests
// ========================================================================

class ListBagsTest : public UtilsTest {};

TEST_F( ListBagsTest, FindsBags )
{
  createFakeBag( "bag_a" );
  createFakeBag( "bag_b" );
  // Also create a non-bag directory (should be ignored)
  fs::create_directories( tmp_dir_ / "not_a_bag" );

  std::vector<hector_recorder_msgs::msg::BagInfo> bags;
  bool success = false;
  std::string message;
  rosbag2_storage::StorageOptions storage;
  storage.uri = tmp_dir_.string();

  handleListBags( "", storage, bags, success, message );

  EXPECT_TRUE( success );
  EXPECT_EQ( bags.size(), 2u );
}

TEST_F( ListBagsTest, ExplicitPath )
{
  createFakeBag( "bag_x" );

  std::vector<hector_recorder_msgs::msg::BagInfo> bags;
  bool success = false;
  std::string message;
  rosbag2_storage::StorageOptions storage;

  handleListBags( tmp_dir_.string(), storage, bags, success, message );

  EXPECT_TRUE( success );
  EXPECT_EQ( bags.size(), 1u );
  EXPECT_EQ( bags[0].name, "bag_x" );
}

TEST_F( ListBagsTest, RecordedByInMetadata )
{
  createFakeBag( "annotated_bag", "alice@robot" );

  std::vector<hector_recorder_msgs::msg::BagInfo> bags;
  bool success = false;
  std::string message;
  rosbag2_storage::StorageOptions storage;

  handleListBags( tmp_dir_.string(), storage, bags, success, message );

  ASSERT_EQ( bags.size(), 1u );
  EXPECT_EQ( bags[0].recorded_by, "alice@robot" );
}

TEST_F( ListBagsTest, InvalidPath )
{
  std::vector<hector_recorder_msgs::msg::BagInfo> bags;
  bool success = true;
  std::string message;
  rosbag2_storage::StorageOptions storage;

  handleListBags( "/nonexistent/path", storage, bags, success, message );

  EXPECT_FALSE( success );
}

TEST_F( ListBagsTest, EmptyDirectory )
{
  std::vector<hector_recorder_msgs::msg::BagInfo> bags;
  bool success = false;
  std::string message;
  rosbag2_storage::StorageOptions storage;

  handleListBags( tmp_dir_.string(), storage, bags, success, message );

  EXPECT_TRUE( success );
  EXPECT_EQ( bags.size(), 0u );
}

// ========================================================================
// handleGetBagDetails tests
// ========================================================================

class BagDetailsTest : public UtilsTest {};

TEST_F( BagDetailsTest, ReadsDetails )
{
  auto bag = createFakeBag( "detail_bag", "bob@pc" );

  hector_recorder_msgs::msg::BagInfo info;
  std::vector<hector_recorder_msgs::msg::BagTopicInfo> topics;
  bool success = false;
  std::string message;

  handleGetBagDetails( bag.string(), info, topics, success, message );

  EXPECT_TRUE( success );
  EXPECT_EQ( info.name, "detail_bag" );
  EXPECT_EQ( info.recorded_by, "bob@pc" );
  EXPECT_EQ( info.message_count, 42u );
  EXPECT_GT( info.size_bytes, 0u );
  EXPECT_DOUBLE_EQ( info.duration_secs, 5.0 );

  ASSERT_EQ( topics.size(), 1u );
  EXPECT_EQ( topics[0].name, "/test_topic" );
  EXPECT_EQ( topics[0].type, "std_msgs/msg/String" );
  EXPECT_EQ( topics[0].message_count, 42u );
}

TEST_F( BagDetailsTest, InvalidPath )
{
  hector_recorder_msgs::msg::BagInfo info;
  std::vector<hector_recorder_msgs::msg::BagTopicInfo> topics;
  bool success = true;
  std::string message;

  handleGetBagDetails( "/nonexistent/bag", info, topics, success, message );

  EXPECT_FALSE( success );
}

// ========================================================================
// resolveOutputUriToAbsolute tests
// ========================================================================

TEST( ResolveUriTest, RelativePath )
{
  std::string result = resolveOutputUriToAbsolute( "bags/" );
  EXPECT_TRUE( fs::path( result ).is_absolute() );
}

TEST( ResolveUriTest, AbsolutePath )
{
  std::string result = resolveOutputUriToAbsolute( "/tmp/bags" );
  EXPECT_EQ( result, "/tmp/bags" );
}

TEST( ResolveUriTest, TildeExpansion )
{
  const char *home = std::getenv( "HOME" );
  if ( !home )
    GTEST_SKIP() << "HOME not set";

  std::string result = resolveOutputUriToAbsolute( "~/bags" );
  EXPECT_TRUE( result.find( home ) == 0 );
  EXPECT_TRUE( result.find( "~" ) == std::string::npos );
}
