#include "bag_recorder_engine.hpp"

#include <QDateTime>

#include <algorithm>
#include <filesystem>
#include <unistd.h>

#include <rclcpp/context.hpp>
#include <rclcpp/init_options.hpp>
#include <rclcpp/qos.hpp>
#include <rmw/rmw.h>
#include <rosbag2_storage/qos.hpp>
#include <rosbag2_storage/storage_options.hpp>

namespace fs = std::filesystem;

// ============================================================================
// Helpers
// ============================================================================

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

BagRecorderEngine::BagRecorderEngine( QObject *parent ) : QObject( parent )
{
  statsTimer_.setInterval( 1000 ); // 1 Hz stats updates
  connect( &statsTimer_, &QTimer::timeout, this, &BagRecorderEngine::onStatsTick );
}

BagRecorderEngine::~BagRecorderEngine()
{
  if ( state_ != "idle" ) {
    stopping_ = true;
    destroySubscriptions();
    {
      std::lock_guard<std::mutex> lock( writerMutex_ );
      if ( writer_ ) {
        try {
          writer_->close();
        } catch ( ... ) {
        }
        writer_.reset();
      }
    }
  }
  shutdownNode();
}

// ============================================================================
// Property Getters
// ============================================================================

QString BagRecorderEngine::state() const { return state_; }
QString BagRecorderEngine::outputDir() const { return outputDir_; }
QString BagRecorderEngine::recordedBy() const { return recordedBy_; }
QString BagRecorderEngine::currentBagPath() const { return currentBagPath_; }

double BagRecorderEngine::duration() const
{
  if ( state_ == "idle" )
    return 0.0;
  auto elapsed = std::chrono::steady_clock::now() - recordingStart_;
  return std::chrono::duration<double>( elapsed ).count();
}

double BagRecorderEngine::totalSize() const { return totalSize_; }
int BagRecorderEngine::messageCount() const { return totalMessageCount_; }
int BagRecorderEngine::topicCount() const { return static_cast<int>( subscriptions_.size() ); }
QString BagRecorderEngine::errorMessage() const { return errorMessage_; }

// ============================================================================
// Property Setters
// ============================================================================

void BagRecorderEngine::setOutputDir( const QString &dir )
{
  if ( outputDir_ != dir ) {
    outputDir_ = dir;
    emit outputDirChanged();
  }
}

void BagRecorderEngine::setRecordedBy( const QString &name )
{
  if ( recordedBy_ != name ) {
    recordedBy_ = name;
    emit recordedByChanged();
  }
}

// ============================================================================
// State Management
// ============================================================================

void BagRecorderEngine::setState( const QString &s )
{
  if ( state_ == s )
    return;
  state_ = s;
  emit stateChanged();
}

void BagRecorderEngine::setError( const QString &msg )
{
  errorMessage_ = msg;
  emit errorMessageChanged();
}

// ============================================================================
// Topic Discovery
// ============================================================================

QVariantList BagRecorderEngine::discoverTopics()
{
  ensureNode();

  QVariantList result;
  auto topics = node_->get_topic_names_and_types();

  for ( const auto &[name, types] : topics ) {
    // Skip internal/hidden topics
    if ( name.find( "/_" ) != std::string::npos )
      continue;

    // Get publisher count
    auto pubs = node_->get_publishers_info_by_topic( name );

    QVariantMap entry;
    entry["name"] = QString::fromStdString( name );
    entry["type"] = types.empty() ? QString() : QString::fromStdString( types[0] );
    entry["publisherCount"] = static_cast<int>( pubs.size() );
    result.append( entry );
  }

  return result;
}

// ============================================================================
// Recording Control
// ============================================================================

void BagRecorderEngine::startRecording( const QStringList &topics, const QString &outputDir )
{
  if ( state_ != "idle" ) {
    setError( "Already recording — stop first" );
    return;
  }

  if ( topics.isEmpty() ) {
    setError( "No topics selected" );
    return;
  }

  setError( "" );
  ensureNode();

  // Determine output directory
  std::string dir = expandHome(
      ( outputDir.isEmpty() ? outputDir_ : outputDir ).toStdString() );
  if ( dir.empty() ) {
    dir = expandHome( "~/bags" );
  }
  // Ensure trailing slash
  if ( dir.back() != '/' )
    dir += '/';

  // Create output directory if needed
  std::error_code ec;
  fs::create_directories( dir, ec );
  if ( ec ) {
    setError( QString( "Failed to create output directory: %1" )
                  .arg( QString::fromStdString( ec.message() ) ) );
    return;
  }

  // Generate bag name
  std::string bagName =
      QDateTime::currentDateTime().toString( "yyyy-MM-dd_HH-mm-ss" ).toStdString();
  std::string bagPath = dir + bagName;

  try {
    // Open writer
    writer_ = std::make_unique<rosbag2_cpp::Writer>();

    rosbag2_storage::StorageOptions storage_options;
    storage_options.uri = bagPath;
    storage_options.storage_id = "mcap";
    storage_options.max_cache_size = 10 * 1024 * 1024; // 10 MB cache

    // Store recorded_by in bag custom_data so it persists in metadata.yaml
    if ( !recordedBy_.isEmpty() ) {
      storage_options.custom_data["recorded_by"] = recordedBy_.toStdString();
    } else {
      // Default: $USER@hostname
      std::string user;
      if ( const char *u = std::getenv( "USER" ) )
        user = u;
      char hostname[256] = {};
      gethostname( hostname, sizeof( hostname ) );
      storage_options.custom_data["recorded_by"] = user + "@" + hostname;
    }

    writer_->open( storage_options );

    currentBagPath_ = QString::fromStdString( bagPath );
    emit currentBagPathChanged();

  } catch ( const std::exception &e ) {
    setError( QString( "Failed to open bag for writing: %1" ).arg( e.what() ) );
    writer_.reset();
    return;
  }

  // Reset statistics
  {
    std::lock_guard<std::mutex> lock( statsMutex_ );
    topicStats_.clear();
    totalMessageCount_ = 0;
    totalSize_ = 0.0;
  }

  paused_ = false;
  stopping_ = false;

  // Create subscriptions for each topic
  auto allTopics = node_->get_topic_names_and_types();

  for ( const auto &topicName : topics ) {
    // Strip surrounding quotes that QML may add during QVariant->QString conversion
    QString cleaned = topicName;
    if ( cleaned.startsWith( '"' ) && cleaned.endsWith( '"' ) ) {
      cleaned = cleaned.mid( 1, cleaned.length() - 2 );
    }
    std::string name = cleaned.toStdString();

    // Find the type for this topic
    auto it = allTopics.find( name );
    if ( it == allTopics.end() || it->second.empty() ) {
      qWarning( "BagRecorderEngine: topic '%s' not found on graph, skipping", name.c_str() );
      continue;
    }
    std::string type = it->second[0];

    // Adapt QoS to match publisher offers (handles transient_local, best_effort, etc.)
    rclcpp::QoS qos( 10 );
    int pubCount = 0;
    try {
      auto pubs = node_->get_publishers_info_by_topic( name );
      pubCount = static_cast<int>( pubs.size() );
      if ( !pubs.empty() ) {
        qos = rosbag2_storage::Rosbag2QoS::adapt_request_to_offers( name, pubs );
      }
    } catch ( ... ) {
    }

    // Create topic in writer
    rosbag2_storage::TopicMetadata topic_metadata;
    topic_metadata.name = name;
    topic_metadata.type = type;
    topic_metadata.serialization_format = rmw_get_serialization_format();
    try {
      writer_->create_topic( topic_metadata );
    } catch ( const std::exception &e ) {
      qWarning( "BagRecorderEngine: failed to create topic '%s': %s", name.c_str(), e.what() );
      continue;
    }

    // Initialize stats
    {
      std::lock_guard<std::mutex> lock( statsMutex_ );
      TopicStats &stats = topicStats_[name];
      stats.type = type;
      stats.publisherCount = pubCount;
      stats.windowStart = std::chrono::steady_clock::now();
    }

    // Create subscription
    try {
      auto sub = node_->create_generic_subscription(
          name, type, qos,
          [this, name, type]( std::shared_ptr<const rclcpp::SerializedMessage> msg ) {
            if ( paused_.load( std::memory_order_relaxed ) ||
                 stopping_.load( std::memory_order_relaxed ) )
              return;

            size_t msgSize = msg->size();

            // Write to bag
            {
              std::lock_guard<std::mutex> lock( writerMutex_ );
              if ( writer_ ) {
                try {
                  auto now_ns = node_->now().nanoseconds();
                  writer_->write( msg, name, type, now_ns, now_ns );
                } catch ( ... ) {
                  return;
                }
              }
            }

            // Update stats
            {
              std::lock_guard<std::mutex> lock( statsMutex_ );
              auto &s = topicStats_[name];
              s.msgCount++;
              s.totalBytes += static_cast<int64_t>( msgSize );
              s.windowMsgs++;
              s.windowBytes += static_cast<int64_t>( msgSize );
              totalMessageCount_++;
              totalSize_ += static_cast<double>( msgSize );
            }
          } );

      subscriptions_[name] = sub;
    } catch ( const std::exception &e ) {
      qWarning( "BagRecorderEngine: failed to subscribe to '%s': %s", name.c_str(), e.what() );
    }
  }

  if ( subscriptions_.empty() ) {
    setError( "Failed to subscribe to any topics" );
    writer_->close();
    writer_.reset();
    return;
  }

  recordingStart_ = std::chrono::steady_clock::now();
  statsTimer_.start();
  setState( "recording" );
}

void BagRecorderEngine::stopRecording()
{
  if ( state_ == "idle" )
    return;
  if ( stopping_ )
    return;

  stopping_ = true;
  statsTimer_.stop();

  // Destroy subscriptions first so no new messages arrive
  destroySubscriptions();

  // Close writer
  QString bagPath = currentBagPath_;
  {
    std::lock_guard<std::mutex> lock( writerMutex_ );
    if ( writer_ ) {
      try {
        writer_->close();
      } catch ( ... ) {
      }
      writer_.reset();
    }
  }

  paused_ = false;
  stopping_ = false;
  setState( "idle" );
  emit recordingFinished( bagPath );
}

void BagRecorderEngine::pauseRecording()
{
  if ( state_ != "recording" )
    return;
  paused_ = true;
  setState( "paused" );
}

void BagRecorderEngine::resumeRecording()
{
  if ( state_ != "paused" )
    return;
  paused_ = false;
  setState( "recording" );
}

void BagRecorderEngine::splitBag()
{
  if ( state_ == "idle" )
    return;

  std::lock_guard<std::mutex> lock( writerMutex_ );
  if ( writer_ ) {
    try {
      writer_->split_bagfile();
    } catch ( const std::exception &e ) {
      setError( QString( "Split failed: %1" ).arg( e.what() ) );
    }
  }
}

// ============================================================================
// Statistics
// ============================================================================

QVariantList BagRecorderEngine::getTopicStats()
{
  QVariantList result;
  std::lock_guard<std::mutex> lock( statsMutex_ );

  for ( const auto &[name, stats] : topicStats_ ) {
    QVariantMap entry;
    entry["topic"] = QString::fromStdString( name );
    entry["type"] = QString::fromStdString( stats.type );
    entry["msgCount"] = static_cast<int>( stats.msgCount );
    entry["frequency"] = stats.frequency;
    entry["size"] = static_cast<double>( stats.totalBytes );
    entry["bandwidth"] = stats.bandwidth;
    entry["publisherCount"] = stats.publisherCount;
    result.append( entry );
  }

  return result;
}

void BagRecorderEngine::onStatsTick()
{
  auto now = std::chrono::steady_clock::now();

  {
    std::lock_guard<std::mutex> lock( statsMutex_ );
    for ( auto &[name, stats] : topicStats_ ) {
      double dt = std::chrono::duration<double>( now - stats.windowStart ).count();
      if ( dt > 0.5 ) {
        stats.frequency = static_cast<double>( stats.windowMsgs ) / dt;
        stats.bandwidth = static_cast<double>( stats.windowBytes ) / dt;
        stats.windowMsgs = 0;
        stats.windowBytes = 0;
        stats.windowStart = now;
      }
    }
  }

  emit statsChanged();
}

// ============================================================================
// Node / Subscription Management
// ============================================================================

void BagRecorderEngine::ensureNode()
{
  if ( node_ )
    return;

  // Dedicated context — same pattern as BagPlayerEngine
  ctx_ = std::make_shared<rclcpp::Context>();
  rclcpp::InitOptions init_options;
  init_options.shutdown_on_signal = false;
  ctx_->init( 0, nullptr, init_options );

  rclcpp::NodeOptions node_options;
  node_options.context( ctx_ );
  node_options.start_parameter_services( false );
  node_options.start_parameter_event_publisher( false );
  node_ = std::make_shared<rclcpp::Node>( "rqml_bag_recorder", node_options );

  // Spin the node in a background thread so subscription callbacks fire
  rclcpp::ExecutorOptions exec_options;
  exec_options.context = ctx_;
  executor_ = std::make_unique<rclcpp::executors::SingleThreadedExecutor>( exec_options );
  executor_->add_node( node_ );
  executorThread_ = std::thread( [this]() { executor_->spin(); } );
}

void BagRecorderEngine::shutdownNode()
{
  if ( executor_ ) {
    executor_->cancel();
  }
  if ( ctx_ ) {
    ctx_->shutdown( "BagRecorderEngine shutting down" );
  }
  if ( executorThread_.joinable() ) {
    executorThread_.join();
  }
  executor_.reset();
  node_.reset();
  ctx_.reset();
}

void BagRecorderEngine::destroySubscriptions()
{
  subscriptions_.clear();
}
