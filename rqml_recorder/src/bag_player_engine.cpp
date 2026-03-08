#include "bag_player_engine.hpp"

#include <QFileInfo>

#include <algorithm>
#include <chrono>
#include <filesystem>

#include <rclcpp/context.hpp>
#include <rclcpp/init_options.hpp>
#include <rclcpp/serialized_message.hpp>
#include <rosbag2_storage/storage_filter.hpp>

namespace fs = std::filesystem;

// ============================================================================
// Helpers
// ============================================================================

/// Expand ~ at the start of a path
static std::string expandHome( const std::string &path )
{
  if ( path.empty() || path[0] != '~' )
    return path;
  const char *home = std::getenv( "HOME" );
  if ( !home )
    return path;
  return std::string( home ) + path.substr( 1 );
}

// ============================================================================
// Construction / Destruction
// ============================================================================

BagPlayerEngine::BagPlayerEngine( QObject *parent ) : QObject( parent )
{
  playbackTimer_.setTimerType( Qt::PreciseTimer );
  playbackTimer_.setInterval( 1 ); // 1ms tick
  connect( &playbackTimer_, &QTimer::timeout, this, &BagPlayerEngine::onPlaybackTick );

  clockTimer_.setTimerType( Qt::PreciseTimer );
  connect( &clockTimer_, &QTimer::timeout, this, &BagPlayerEngine::onClockTick );
}

BagPlayerEngine::~BagPlayerEngine()
{
  stop();
  destroyPublishers();
  node_.reset();
}

// ============================================================================
// Property Getters
// ============================================================================

QString BagPlayerEngine::bagPath() const { return bagPath_; }
QString BagPlayerEngine::bagName() const { return bagName_; }
QString BagPlayerEngine::state() const { return state_; }
double BagPlayerEngine::rate() const { return rate_; }
bool BagPlayerEngine::looping() const { return looping_; }
double BagPlayerEngine::duration() const { return duration_; }

double BagPlayerEngine::currentTime() const
{
  if ( bagStartNs_ == 0 )
    return 0.0;
  return static_cast<double>( currentBagTimeNs_ - bagStartNs_ ) * 1e-9;
}

double BagPlayerEngine::progress() const
{
  if ( duration_ <= 0.0 )
    return 0.0;
  return std::clamp( currentTime() / duration_, 0.0, 1.0 );
}

bool BagPlayerEngine::clockEnabled() const { return clockEnabled_; }
double BagPlayerEngine::clockFrequency() const { return clockFrequency_; }
int BagPlayerEngine::topicCount() const { return topicCount_; }
int BagPlayerEngine::messageCount() const { return messageCount_; }
QStringList BagPlayerEngine::topicList() const { return topicList_; }
QString BagPlayerEngine::errorMessage() const { return errorMessage_; }

// ============================================================================
// Property Setters
// ============================================================================

void BagPlayerEngine::setRate( double rate )
{
  if ( rate <= 0.0 )
    return;
  if ( qFuzzyCompare( rate_, rate ) )
    return;
  rate_ = rate;

  // Reset timing anchor so rate change takes effect smoothly
  if ( state_ == "playing" ) {
    wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
    lastMsgBagTimeNs_ = currentBagTimeNs_;
  }

  emit rateChanged();
}

void BagPlayerEngine::setLooping( bool looping )
{
  if ( looping_ == looping )
    return;
  looping_ = looping;
  emit loopingChanged();
}

void BagPlayerEngine::setClockEnabled( bool enabled )
{
  if ( clockEnabled_ == enabled )
    return;
  clockEnabled_ = enabled;

  if ( enabled && node_ && !clockPublisher_ ) {
    clockPublisher_ = node_->create_publisher<rosgraph_msgs::msg::Clock>(
        "/clock", rclcpp::ClockQoS() );
  }
  if ( enabled && ( state_ == "playing" ) ) {
    clockTimer_.start( static_cast<int>( 1000.0 / clockFrequency_ ) );
  } else {
    clockTimer_.stop();
  }

  emit clockEnabledChanged();
}

void BagPlayerEngine::setClockFrequency( double hz )
{
  if ( hz <= 0.0 )
    return;
  if ( qFuzzyCompare( clockFrequency_, hz ) )
    return;
  clockFrequency_ = hz;
  if ( clockTimer_.isActive() ) {
    clockTimer_.setInterval( static_cast<int>( 1000.0 / hz ) );
  }
  emit clockFrequencyChanged();
}

// ============================================================================
// State Management
// ============================================================================

void BagPlayerEngine::setState( const QString &s )
{
  if ( state_ == s )
    return;
  state_ = s;
  emit stateChanged();
}

void BagPlayerEngine::setError( const QString &msg )
{
  errorMessage_ = msg;
  emit errorMessageChanged();
}

// ============================================================================
// Load
// ============================================================================

void BagPlayerEngine::load( const QString &bagPath )
{
  // Stop any current playback — must fully complete before we proceed
  stop();

  std::string path = expandHome( bagPath.toStdString() );

  if ( !fs::is_directory( path ) ) {
    setError( "Not a directory: " + bagPath );
    return;
  }

  setState( "loading" );
  setError( "" );

  try {
    reader_ = std::make_unique<rosbag2_cpp::Reader>();
    reader_->open( path );

    auto metadata = reader_->get_metadata();

    bagPath_ = bagPath;
    bagName_ = QString::fromStdString( fs::path( path ).filename().string() );
    duration_ = std::chrono::duration<double>( metadata.duration ).count();
    bagStartNs_ = std::chrono::duration_cast<std::chrono::nanoseconds>(
                      metadata.starting_time.time_since_epoch() )
                      .count();
    bagEndNs_ = bagStartNs_ + std::chrono::duration_cast<std::chrono::nanoseconds>(
                                  metadata.duration )
                                  .count();
    messageCount_ = static_cast<int>( metadata.message_count );

    topicList_.clear();
    for ( const auto &ti : metadata.topics_with_message_count ) {
      topicList_.append( QString::fromStdString( ti.topic_metadata.name ) );
    }
    topicList_.sort();
    topicCount_ = topicList_.size();

    currentBagTimeNs_ = bagStartNs_;

    emit bagPathChanged();
    emit metadataChanged();
    emit progressChanged();
    setState( "loaded" );
  } catch ( const std::exception &e ) {
    setError( QString( "Failed to open bag: %1" ).arg( e.what() ) );
    reader_.reset();
    setState( "idle" );
  }
}

// ============================================================================
// Playback Control
// ============================================================================

void BagPlayerEngine::play( const QStringList &topicFilter )
{
  if ( !reader_ ) {
    setError( "No bag loaded" );
    return;
  }

  if ( state_ == "playing" )
    return;

  // If we were stopped/loaded, set up filter and seek to start
  if ( state_ == "loaded" || state_ == "finished" ) {
    // Store and apply topic filter
    activeFilter_ = {};
    if ( !topicFilter.isEmpty() ) {
      for ( const auto &t : topicFilter ) {
        activeFilter_.topics.push_back( t.toStdString() );
      }
      reader_->set_filter( activeFilter_ );
    } else {
      reader_->reset_filter();
    }

    // Create publishers for the topics we'll play
    createPublishers( topicFilter );

    // Seek to start
    reader_->seek( bagStartNs_ );
    currentBagTimeNs_ = bagStartNs_;
    firstMessage_ = true;
  }

  // Start timers
  wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
  lastMsgBagTimeNs_ = currentBagTimeNs_;
  playbackTimer_.start();

  if ( clockEnabled_ ) {
    if ( !clockPublisher_ ) {
      ensureNode();
      clockPublisher_ = node_->create_publisher<rosgraph_msgs::msg::Clock>(
          "/clock", rclcpp::ClockQoS() );
    }
    clockTimer_.start( static_cast<int>( 1000.0 / clockFrequency_ ) );
  }

  setState( "playing" );
}

void BagPlayerEngine::pause()
{
  if ( state_ != "playing" )
    return;
  playbackTimer_.stop();
  clockTimer_.stop();
  setState( "paused" );
}

void BagPlayerEngine::resume()
{
  if ( state_ != "paused" )
    return;

  wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
  lastMsgBagTimeNs_ = currentBagTimeNs_;
  playbackTimer_.start();

  if ( clockEnabled_ ) {
    clockTimer_.start( static_cast<int>( 1000.0 / clockFrequency_ ) );
  }

  setState( "playing" );
}

void BagPlayerEngine::stop()
{
  if ( stopping_ )
    return;
  stopping_ = true;

  playbackTimer_.stop();
  clockTimer_.stop();

  // Reset playback state before closing reader to avoid re-entrant access
  pendingMsg_.reset();
  activeFilter_ = {};
  disabledTopics_.clear();
  firstMessage_ = true;

  if ( reader_ ) {
    try {
      reader_->close();
    } catch ( ... ) {
    }
    reader_.reset();
  }

  destroyPublishers();

  currentBagTimeNs_ = bagStartNs_;
  emit progressChanged();
  setState( "idle" );

  stopping_ = false;
}

void BagPlayerEngine::seek( double seconds )
{
  if ( !reader_ && ( state_ == "idle" || state_ == "loading" ) )
    return;

  rcutils_time_point_value_t target_ns =
      bagStartNs_ + static_cast<rcutils_time_point_value_t>( seconds * 1e9 );
  target_ns = std::clamp( target_ns, bagStartNs_, bagEndNs_ );

  // Reader::seek can fail or behave oddly if the bag was fully consumed.
  // Reopen the bag and seek to the target.
  reopenAndSeek( target_ns );

  currentBagTimeNs_ = target_ns;
  pendingMsg_.reset();

  // Reset timing anchor
  wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
  lastMsgBagTimeNs_ = currentBagTimeNs_;
  firstMessage_ = true;

  emit progressChanged();
}

bool BagPlayerEngine::stepForward()
{
  if ( state_ != "paused" && state_ != "loaded" )
    return false;
  if ( !reader_ )
    return false;

  return publishNextMessage();
}

void BagPlayerEngine::setTopicEnabled( const QString &topic, bool enabled )
{
  std::string t = topic.toStdString();
  if ( enabled ) {
    disabledTopics_.erase( t );
  } else {
    disabledTopics_.insert( t );
  }
}

// ============================================================================
// Playback Timer
// ============================================================================

void BagPlayerEngine::onPlaybackTick()
{
  if ( !reader_ || stopping_ )
    return;

  // Publish as many messages as are "due" based on wall clock and rate
  int published = 0;
  const int maxPerTick = 100; // prevent UI freeze on high-rate bags

  while ( published < maxPerTick ) {
    // Get the next message — either from the pending buffer or from the reader
    std::shared_ptr<rosbag2_storage::SerializedBagMessage> msg;

    if ( pendingMsg_ ) {
      msg = std::move( pendingMsg_ );
    } else {
      if ( !reader_->has_next() ) {
        // End of bag
        if ( looping_ ) {
          reopenAndSeek( bagStartNs_ );
          currentBagTimeNs_ = bagStartNs_;
          wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
          lastMsgBagTimeNs_ = bagStartNs_;
          firstMessage_ = true;
          continue;
        }

        playbackTimer_.stop();
        clockTimer_.stop();
        setState( "finished" );
        emit playbackFinished();
        return;
      }

      msg = reader_->read_next();
      if ( !msg )
        continue;
    }

    if ( firstMessage_ ) {
      // First message — publish immediately, set timing anchor
      wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
      lastMsgBagTimeNs_ = msg->recv_timestamp;
      currentBagTimeNs_ = msg->recv_timestamp;
      firstMessage_ = false;
    } else {
      // Check if this message is due
      auto now = std::chrono::steady_clock::now();
      double bag_delta_s =
          static_cast<double>( msg->recv_timestamp - lastMsgBagTimeNs_ ) * 1e-9;

      // Skip negative deltas (out-of-order timestamps)
      if ( bag_delta_s < 0.0 ) {
        bag_delta_s = 0.0;
      }

      double wall_delta_s = bag_delta_s / rate_;
      auto wall_elapsed = std::chrono::duration<double>( now - wallTimeAtLastMsg_ ).count();

      if ( wall_elapsed < wall_delta_s ) {
        double remaining = wall_delta_s - wall_elapsed;
        if ( remaining > 0.005 ) {
          // Buffer this message and wait — the timer will fire again in 1ms
          pendingMsg_ = std::move( msg );
          return;
        }
        // Small gap — publish anyway for smoothness
      }

      wallTimeAtLastMsg_ = std::chrono::steady_clock::now();
      lastMsgBagTimeNs_ = msg->recv_timestamp;
      currentBagTimeNs_ = msg->recv_timestamp;
    }

    // Publish the message (skip disabled topics)
    if ( disabledTopics_.count( msg->topic_name ) == 0 ) {
      auto it = publishers_.find( msg->topic_name );
      if ( it != publishers_.end() && msg->serialized_data ) {
        try {
          rclcpp::SerializedMessage serialized( *msg->serialized_data );
          it->second->publish( serialized );
        } catch ( ... ) {
          // Skip publish errors (e.g., subscriber mismatch)
        }
      }
    }

    published++;
    emit progressChanged();
  }
}

void BagPlayerEngine::onClockTick()
{
  if ( stopping_ || !clockPublisher_ )
    return;
  if ( currentBagTimeNs_ > 0 ) {
    publishClock( currentBagTimeNs_ );
  }
}

// ============================================================================
// Message Publishing
// ============================================================================

bool BagPlayerEngine::publishNextMessage()
{
  if ( !reader_ || !reader_->has_next() )
    return false;

  auto msg = reader_->read_next();
  if ( !msg )
    return false;

  currentBagTimeNs_ = msg->recv_timestamp;

  if ( disabledTopics_.count( msg->topic_name ) == 0 ) {
    auto it = publishers_.find( msg->topic_name );
    if ( it != publishers_.end() && msg->serialized_data ) {
      try {
        rclcpp::SerializedMessage serialized( *msg->serialized_data );
        it->second->publish( serialized );
      } catch ( ... ) {
      }
    }
  }

  emit progressChanged();
  return true;
}

void BagPlayerEngine::publishClock( rcutils_time_point_value_t bag_time_ns )
{
  if ( !clockPublisher_ )
    return;

  rosgraph_msgs::msg::Clock clock_msg;
  clock_msg.clock.sec = static_cast<int32_t>( bag_time_ns / 1000000000LL );
  clock_msg.clock.nanosec = static_cast<uint32_t>( bag_time_ns % 1000000000LL );
  clockPublisher_->publish( clock_msg );
}

// ============================================================================
// Publisher Management
// ============================================================================

void BagPlayerEngine::ensureNode()
{
  if ( node_ )
    return;

  // Use a dedicated context so our node doesn't interfere with the main
  // rqml rclcpp context's signal handling / shutdown behaviour.
  auto ctx = std::make_shared<rclcpp::Context>();
  rclcpp::InitOptions init_options;
  init_options.shutdown_on_signal = false;
  ctx->init( 0, nullptr, init_options );

  rclcpp::NodeOptions node_options;
  node_options.context( ctx );
  node_options.start_parameter_services( false );
  node_options.start_parameter_event_publisher( false );
  node_ = std::make_shared<rclcpp::Node>( "rqml_bag_player", node_options );
}

void BagPlayerEngine::createPublishers( const QStringList &topicFilter )
{
  if ( !reader_ )
    return;

  ensureNode();
  destroyPublishers();

  auto topics = reader_->get_all_topics_and_types();

  for ( const auto &topic : topics ) {
    // Check filter
    if ( !topicFilter.isEmpty() ) {
      bool found = false;
      for ( const auto &f : topicFilter ) {
        if ( f.toStdString() == topic.name ) {
          found = true;
          break;
        }
      }
      if ( !found )
        continue;
    }

    try {
      // Determine QoS from the bag's offered profiles
      rclcpp::QoS qos( 10 );
      if ( !topic.offered_qos_profiles.empty() ) {
        qos = topic.offered_qos_profiles[0];
      }

      auto pub = node_->create_generic_publisher( topic.name, topic.type, qos );
      publishers_[topic.name] = pub;
    } catch ( const std::exception &e ) {
      // Skip topics we can't create publishers for
      qWarning( "BagPlayerEngine: Failed to create publisher for %s: %s",
                topic.name.c_str(), e.what() );
    }
  }
}

void BagPlayerEngine::destroyPublishers()
{
  publishers_.clear();
  clockPublisher_.reset();
}

// ============================================================================
// Reader Helpers
// ============================================================================

void BagPlayerEngine::reopenAndSeek( rcutils_time_point_value_t target_ns )
{
  if ( bagPath_.isEmpty() )
    return;

  std::string path = expandHome( bagPath_.toStdString() );

  try {
    if ( reader_ ) {
      reader_->close();
    }
    reader_ = std::make_unique<rosbag2_cpp::Reader>();
    reader_->open( path );
    if ( !activeFilter_.topics.empty() ) {
      reader_->set_filter( activeFilter_ );
    }
    reader_->seek( target_ns );
  } catch ( const std::exception &e ) {
    setError( QString( "Failed to reopen bag: %1" ).arg( e.what() ) );
  }
}
