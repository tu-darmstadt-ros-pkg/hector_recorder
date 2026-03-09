#include "hector_recorder/utils.h"
#include <filesystem>
#include <fstream>

namespace hector_recorder
{
std::string getAbsolutePath( const std::string &path )
{
  try {
    return std::filesystem::canonical( path );
  } catch ( const std::filesystem::filesystem_error &e ) {
    throw std::runtime_error( "Error resolving absolute path for '" + path + "': " + e.what() );
  }
}

static std::string make_timestamped_folder_name()
{
  auto now = std::chrono::system_clock::now();
  std::time_t t = std::chrono::system_clock::to_time_t( now );
  std::tm lt{};
#if defined( _WIN32 )
  localtime_s( &lt, &t );
#else
  localtime_r( &t, &lt );
#endif
  std::ostringstream oss;
  oss << "rosbag2_" << std::put_time( &lt, "%Y_%m_%d-%H_%M_%S" );
  return oss.str();
}

static bool is_rosbag_dir( const fs::path &dir )
{
  const fs::path meta = dir / "metadata.yaml";
  return fs::exists( meta ) && fs::is_regular_file( meta );
}

static fs::path find_rosbag_ancestor( const fs::path &dir )
{
  if ( dir.empty() )
    return {};

  fs::path p = dir;
  while ( true ) {
    if ( fs::exists( p ) && fs::is_directory( p ) && is_rosbag_dir( p ) ) {
      return p;
    }
    fs::path parent = p.parent_path();

    // Important: If parent is the same as p, we are at the root directory
    if ( parent == p || parent.empty() ) {
      break;
    }
    p = parent;
  }
  return {};
}

std::string resolveOutputDirectory( const std::string &output_dir )
{
  const fs::path cwd = fs::current_path();
  const std::string ts = make_timestamped_folder_name();
  const bool had_trailing_sep = !output_dir.empty() && ( output_dir.back() == '/' );

  // Expand ~ and $ENV before any path operations
  const std::string expanded = expandUserAndEnv( output_dir );

  fs::path target; // ← This directory will be created by rosbag2

  if ( expanded.empty() ) {
    // No output_dir → CWD/rosbag2_<timestamp>
    target = cwd / ts;
  } else {
    fs::path p = fs::path( expanded ).lexically_normal();
    const bool exists = fs::exists( p );

    if ( exists ) {
      if ( !fs::is_directory( p ) ) {
        throw std::runtime_error( "Specified output path exists but is not a directory: " +
                                  p.string() );
      }
      if ( is_rosbag_dir( p ) ) {
        // Existing rosbag dir → create timestamped sibling in parent
        target = p.parent_path() / ts;
      } else {
        // Existing directory → timestamped rosbag subdirectory
        target = p / ts;
      }
    } else {
      fs::path par = p.parent_path();
      if ( par.empty() ) {
        // Only one name → Bag under CWD/<name>
        target = cwd / p;
      } else {
        if ( fs::exists( par ) && !fs::is_directory( par ) ) {
          throw std::runtime_error( "Specified output parent exists but is not a directory: " +
                                    par.string() );
        }
        // Trailing Slash signals Container-Semantic → timestamped directory
        // Else: Just use the name as bag directory
        target = had_trailing_sep ? ( p / ts ) : p;
      }
    }
  }

  const fs::path container = target.parent_path();

  // Impede placing a new rosbag inside an existing rosbag directory
  if ( !container.empty() ) {
    if ( fs::path bad = find_rosbag_ancestor( container ); !bad.empty() ) {
      throw std::runtime_error( "Cannot place a new rosbag inside an existing rosbag directory: " +
                                bad.string() );
    }
  }

  // Target directory must not exist yet
  if ( fs::exists( target ) ) {
    throw std::runtime_error( "Target directory already exists: " + target.string() );
  }

  // Create the parent directory if it does not exist
  try {
    if ( !container.empty() && !fs::exists( container ) ) {
      fs::create_directories( container );
    }
  } catch ( const fs::filesystem_error &e ) {
    throw std::runtime_error( "Failed to create parent directories for '" + container.string() +
                              "': " + e.what() );
  }

  return target.string();
}

std::string formatMemory( uint64_t bytes )
{
  if ( bytes < ( 1ull << 10 ) )
    return fmt::format( "{:.1f} B", static_cast<double>( bytes ) );
  else if ( bytes < ( 1ull << 20 ) )
    return fmt::format( "{:.1f} KiB", static_cast<double>( bytes ) / ( 1ull << 10 ) );
  else if ( bytes < ( 1ull << 30 ) )
    return fmt::format( "{:.1f} MiB", static_cast<double>( bytes ) / ( 1ull << 20 ) );
  else if ( bytes < ( 1ull << 40 ) )
    return fmt::format( "{:.1f} GiB", static_cast<double>( bytes ) / ( 1ull << 30 ) );
  else
    return fmt::format( "{:.1f} TiB", static_cast<double>( bytes ) / ( 1ull << 40 ) );
}

std::string rateToString( double rate )
{
  if ( rate < 1000.0 )
    return fmt::format( "{:.1f} Hz", rate );
  else if ( rate < 1e6 )
    return fmt::format( "{:.1f} kHz", rate / 1e3 );
  else
    return fmt::format( "{:.1f} MHz", rate / 1e6 );
}

std::string bandwidthToString( double bandwidth )
{
  if ( bandwidth < 1000.0 )
    return fmt::format( "{:.1f} B/s", bandwidth );
  else if ( bandwidth < 1000.0 * 1000.0 )
    return fmt::format( "{:.1f} kB/s", bandwidth / 1000.0 );
  else if ( bandwidth < 1000.0 * 1000.0 * 1000.0 )
    return fmt::format( "{:.1f} MB/s", bandwidth / ( 1000.0 * 1000.0 ) );
  else
    return fmt::format( "{:.1f} GB/s", bandwidth / ( 1000.0 * 1000.0 * 1000.0 ) );
}

int calculateRequiredLines( const std::vector<std::string> &lines )
{
  return static_cast<int>( lines.size() ) + 2; // +2 for borders
}

std::string clipString( const std::string &str, int max_length )
{
  if ( static_cast<int>( str.size() ) <= max_length ) {
    return str;
  }

  // Find the position of the last '/'
  size_t last_slash_pos = str.rfind( '/' );
  if ( last_slash_pos == std::string::npos || last_slash_pos == 0 ) {
    // If no '/' is found or it's the first character, fallback to simple clipping
    return str.substr( 0, max_length - 3 ) + "...";
  }

  std::string suffix = str.substr( last_slash_pos ); // Include the '/' in the suffix
  int suffix_length = static_cast<int>( suffix.size() );
  int prefix_length = max_length - suffix_length - 3; // Account for "..."

  if ( prefix_length <= 0 ) {
    // If the suffix alone exceeds the max length, truncate it
    return "..." + suffix.substr( suffix.size() - ( max_length - 3 ) );
  }

  std::string prefix = str.substr( 0, prefix_length );
  return prefix + "..." + suffix;
}

void ensureLeadingSlash( std::vector<std::string> &vector )
{
  if ( !vector.empty() ) {
    for ( auto &string : vector ) {
      if ( string.find( "/" ) != 0 ) {
        string = "/" + string;
      }
    }
  }
}

static std::string expandUserAndEnv( std::string s )
{
  // ~ → $HOME
  if ( !s.empty() && s[0] == '~' ) {
    const char *home = std::getenv( "HOME" );
    if ( home && s.size() == 1 ) {
      s = home;
    } else if ( home && s.size() > 1 && s[1] == '/' ) {
      s = std::string( home ) + s.substr( 1 );
    }
    // (If "~user" needed, implement lookup; omitted for simplicity.)
  }

  // Walk through regex matches, replacing each captured variable name (capture group 1)
  // with its environment value. Text between matches is copied verbatim.
  auto replace_env = []( const std::string &in, const std::regex &re ) {
    std::string out;
    std::sregex_iterator it( in.begin(), in.end(), re ), end;
    size_t last = 0;
    out.reserve( in.size() );
    for ( ; it != end; ++it ) {
      out.append( in, last, it->position() - last );
      std::string key = it->size() > 1 ? ( *it )[1].str() : "";
      const char *val = key.empty() ? nullptr : std::getenv( key.c_str() );
      out += ( val ? val : "" );
      last = it->position() + it->length();
    }
    out.append( in, last, std::string::npos );
    return out;
  };

  // ${VAR}
  s = replace_env( s, std::regex( R"(\$\{([A-Za-z_][A-Za-z0-9_]*)\})" ) );
  // $VAR
  s = replace_env( s, std::regex( R"(\$([A-Za-z_][A-Za-z0-9_]*))" ) );

  return s;
}

std::string resolveOutputUriToAbsolute( const std::string &uri )
{
  std::string expanded = expandUserAndEnv( uri );
  fs::path p( expanded );

  // Make absolute and normalize. weakly_canonical doesn't require existence.
  fs::path abs = fs::absolute( p );
  fs::path norm = fs::weakly_canonical( abs );

  return norm.empty() ? abs.string() : norm.string();
}

} // namespace hector_recorder