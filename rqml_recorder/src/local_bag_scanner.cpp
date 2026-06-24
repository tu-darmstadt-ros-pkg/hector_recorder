#include "local_bag_scanner.hpp"

#include <QHostInfo>
#include <QJSEngine>

#include <chrono>
#include <ctime>
#include <filesystem>
#include <string>

#include <rosbag2_storage/metadata_io.hpp>

namespace fs = std::filesystem;

// ============================================================================
// Helpers
// ============================================================================

/// Compute total size of all files in a directory
static uint64_t directorySize( const fs::path &dir )
{
  uint64_t total = 0;
  std::error_code ec;
  for ( const auto &entry : fs::recursive_directory_iterator( dir, ec ) ) {
    if ( entry.is_regular_file( ec ) ) {
      total += entry.file_size( ec );
    }
  }
  return total;
}

/// Build a QVariantMap with bag summary info from a bag directory
static bool readBagInfo( const fs::path &bag_dir, QVariantMap &out )
{
  rosbag2_storage::MetadataIo metadata_io;
  if ( !metadata_io.metadata_file_exists( bag_dir.string() ) ) {
    return false;
  }

  try {
    auto metadata = metadata_io.read_metadata( bag_dir.string() );

    out["name"] = QString::fromStdString( bag_dir.filename().string() );
    out["path"] = QString::fromStdString( bag_dir.string() );
    out["sizeBytes"] = static_cast<double>( directorySize( bag_dir ) );
    out["storageId"] = QString::fromStdString( metadata.storage_identifier );
    out["topicCount"] = static_cast<int>( metadata.topics_with_message_count.size() );
    out["messageCount"] = static_cast<int>( metadata.message_count );
    out["durationSecs"] = std::chrono::duration<double>( metadata.duration ).count();

    // Format start time as ISO 8601
    auto start_ns = metadata.starting_time.time_since_epoch();
    auto start_sec = std::chrono::duration_cast<std::chrono::seconds>( start_ns );
    std::time_t start_time_t = start_sec.count();
    std::tm lt{};
    localtime_r( &start_time_t, &lt );
    char buf[64];
    std::strftime( buf, sizeof( buf ), "%Y-%m-%dT%H:%M:%S", &lt );
    out["startTime"] = QString( buf );

    // Read recorded_by from custom_data if available
    auto it = metadata.custom_data.find( "recorded_by" );
    out["recordedBy"] = ( it != metadata.custom_data.end() )
                            ? QString::fromStdString( it->second )
                            : QString();

    return true;
  } catch ( const std::exception & ) {
    return false;
  }
}

/// Expand ~ at the start of a path
static std::string expandHome( const std::string &path )
{
  if ( path.empty() || path[0] != '~' ) {
    return path;
  }
  const char *home = std::getenv( "HOME" );
  if ( !home ) {
    return path;
  }
  return std::string( home ) + path.substr( 1 );
}

// ============================================================================
// LocalBagScanner
// ============================================================================

LocalBagScanner::LocalBagScanner( QObject *parent ) : QObject( parent ) {}

QString LocalBagScanner::scanPath() const { return scanPath_; }

void LocalBagScanner::setScanPath( const QString &path )
{
  if ( scanPath_ != path ) {
    scanPath_ = path;
    emit scanPathChanged();
  }
}

void LocalBagScanner::listBags( const QString &path, QJSValue callback )
{
  std::string scan_dir = path.isEmpty() ? scanPath_.toStdString() : path.toStdString();
  scan_dir = expandHome( scan_dir );

  // If the path itself is a bag, go up to its parent
  rosbag2_storage::MetadataIo metadata_io;
  if ( metadata_io.metadata_file_exists( scan_dir ) ) {
    scan_dir = fs::path( scan_dir ).parent_path().string();
  }

  QVariantList bags;

  if ( !fs::is_directory( scan_dir ) ) {
    emit serviceResponse( "list_bags", false,
                          QString( "Path is not a directory: %1" )
                              .arg( QString::fromStdString( scan_dir ) ) );
    if ( callback.isCallable() ) {
      callback.call( { QJSValue::NullValue } );
    }
    return;
  }

  std::error_code ec;
  for ( const auto &entry : fs::directory_iterator( scan_dir, ec ) ) {
    if ( !entry.is_directory( ec ) )
      continue;

    QVariantMap info;
    if ( readBagInfo( entry.path(), info ) ) {
      bags.append( info );
    }
  }

  // Sort by startTime descending (newest first)
  std::sort( bags.begin(), bags.end(), []( const QVariant &a, const QVariant &b ) {
    return a.toMap()["startTime"].toString() > b.toMap()["startTime"].toString();
  } );

  if ( callback.isCallable() ) {
    auto *engine = qjsEngine( this );
    if ( engine ) {
      QJSValue jsBags = engine->newArray( bags.size() );
      for ( int i = 0; i < bags.size(); ++i ) {
        QJSValue obj = engine->newObject();
        const auto map = bags[i].toMap();
        for ( auto it = map.cbegin(); it != map.cend(); ++it ) {
          obj.setProperty( it.key(), engine->toScriptValue( it.value() ) );
        }
        jsBags.setProperty( i, obj );
      }
      callback.call( { jsBags } );
    }
  }
}

void LocalBagScanner::getBagDetails( const QString &bagPath, QJSValue callback )
{
  std::string bag_path = expandHome( bagPath.toStdString() );

  QVariantMap info;
  if ( !readBagInfo( bag_path, info ) ) {
    emit serviceResponse( "get_bag_details", false,
                          QString( "Failed to read bag metadata from: %1" ).arg( bagPath ) );
    return;
  }

  QVariantList topics;
  try {
    rosbag2_storage::MetadataIo metadata_io;
    auto metadata = metadata_io.read_metadata( bag_path );

    for ( const auto &topic_info : metadata.topics_with_message_count ) {
      QVariantMap ti;
      ti["name"] = QString::fromStdString( topic_info.topic_metadata.name );
      ti["type"] = QString::fromStdString( topic_info.topic_metadata.type );
      ti["messageCount"] = static_cast<int>( topic_info.message_count );
      ti["serializationFormat"] =
          QString::fromStdString( topic_info.topic_metadata.serialization_format );
      topics.append( ti );
    }
  } catch ( const std::exception &e ) {
    emit serviceResponse( "get_bag_details", false,
                          QString( "Failed to read bag details: %1" ).arg( e.what() ) );
    return;
  }

  if ( callback.isCallable() ) {
    auto *engine = qjsEngine( this );
    if ( engine ) {
      // Convert info map to JS object
      QJSValue jsInfo = engine->newObject();
      for ( auto it = info.cbegin(); it != info.cend(); ++it ) {
        jsInfo.setProperty( it.key(), engine->toScriptValue( it.value() ) );
      }

      // Convert topics list to JS array
      QJSValue jsTopics = engine->newArray( topics.size() );
      for ( int i = 0; i < topics.size(); ++i ) {
        QJSValue obj = engine->newObject();
        const auto map = topics[i].toMap();
        for ( auto it = map.cbegin(); it != map.cend(); ++it ) {
          obj.setProperty( it.key(), engine->toScriptValue( it.value() ) );
        }
        jsTopics.setProperty( i, obj );
      }

      callback.call( { jsInfo, jsTopics } );
    }
  }
}

void LocalBagScanner::deleteBag( const QString &bagPath, QJSValue callback )
{
  std::string bag_path = expandHome( bagPath.toStdString() );

  if ( !fs::is_directory( bag_path ) ) {
    bool success = false;
    QString message = QString( "Not a directory: %1" ).arg( bagPath );
    emit serviceResponse( "delete_bag", success, message );
    if ( callback.isCallable() ) {
      callback.call( { QJSValue( success ), QJSValue( message ) } );
    }
    return;
  }

  // Safety: only delete if it contains a metadata.yaml
  rosbag2_storage::MetadataIo metadata_io;
  if ( !metadata_io.metadata_file_exists( bag_path ) ) {
    bool success = false;
    QString message =
        QString( "Not a valid rosbag directory (no metadata.yaml): %1" ).arg( bagPath );
    emit serviceResponse( "delete_bag", success, message );
    if ( callback.isCallable() ) {
      callback.call( { QJSValue( success ), QJSValue( message ) } );
    }
    return;
  }

  try {
    std::error_code ec;
    auto removed = fs::remove_all( bag_path, ec );
    if ( ec ) {
      bool success = false;
      QString message = QString( "Failed to delete: %1" ).arg( QString::fromStdString( ec.message() ) );
      emit serviceResponse( "delete_bag", success, message );
      if ( callback.isCallable() ) {
        callback.call( { QJSValue( success ), QJSValue( message ) } );
      }
    } else {
      bool success = true;
      QString message = QString( "Deleted %1 (%2 files removed)" )
                            .arg( bagPath )
                            .arg( removed );
      emit serviceResponse( "delete_bag", success, message );
      if ( callback.isCallable() ) {
        callback.call( { QJSValue( success ), QJSValue( message ) } );
      }
    }
  } catch ( const std::exception &e ) {
    bool success = false;
    QString message = QString( "Failed to delete bag: %1" ).arg( e.what() );
    emit serviceResponse( "delete_bag", success, message );
    if ( callback.isCallable() ) {
      callback.call( { QJSValue( success ), QJSValue( message ) } );
    }
  }
}

QStringList LocalBagScanner::completePath( const QString &partial ) const
{
  std::string input = expandHome( partial.toStdString() );
  QStringList results;

  // Determine the parent directory and prefix to match
  fs::path inputPath( input );
  fs::path parentDir;
  std::string prefix;

  if ( input.empty() ) {
    parentDir = "/";
    prefix = "";
  } else if ( input.back() == '/' ) {
    // User typed a complete directory path — list its children
    parentDir = inputPath;
    prefix = "";
  } else {
    // User is mid-typing a name — match against parent's children
    parentDir = inputPath.parent_path();
    prefix = inputPath.filename().string();
  }

  if ( !fs::is_directory( parentDir ) ) {
    return results;
  }

  // Whether the original input started with ~
  bool useTilde = partial.startsWith( "~" );
  std::string home;
  if ( useTilde ) {
    const char *h = std::getenv( "HOME" );
    if ( h )
      home = h;
  }

  std::error_code ec;
  for ( const auto &entry : fs::directory_iterator( parentDir, ec ) ) {
    if ( !entry.is_directory( ec ) )
      continue;

    std::string name = entry.path().filename().string();
    // Skip hidden directories
    if ( !name.empty() && name[0] == '.' )
      continue;

    if ( !prefix.empty() && name.substr( 0, prefix.size() ) != prefix )
      continue;

    std::string fullPath = entry.path().string() + "/";

    // Re-insert ~ if the user typed it
    if ( useTilde && !home.empty() && fullPath.substr( 0, home.size() ) == home ) {
      fullPath = "~" + fullPath.substr( home.size() );
    }

    results.append( QString::fromStdString( fullPath ) );
  }

  results.sort();
  // Limit to a reasonable number
  if ( results.size() > 20 ) {
    results = results.mid( 0, 20 );
  }

  return results;
}

void LocalBagScanner::fetchRecorderInfo( QJSValue callback )
{
  if ( callback.isCallable() ) {
    auto *engine = qjsEngine( this );
    if ( engine ) {
      QJSValue info = engine->newObject();
      info.setProperty( "hostname", QHostInfo::localHostName() );
      QString user = QString::fromLocal8Bit( qgetenv( "USER" ) );
      info.setProperty( "recordedBy",
                        user.isEmpty() ? QHostInfo::localHostName()
                                       : user + "@" + QHostInfo::localHostName() );
      info.setProperty( "configPath", QString() );
      callback.call( { info } );
    }
  }
}
