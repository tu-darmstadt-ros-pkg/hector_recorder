/**
 * @file terminal_ui.cpp
 * @brief Implementation of the TerminalUI class, which provides a terminal-based user interface for
 * monitoring and controlling a ROS 2 recorder.
 *
 * This file contains the implementation of the TerminalUI class, which uses ncurses to display
 * information about the recorder's status, system resources, and recorded topics in a terminal
 * window. It also handles the initialization and cleanup of the recorder and UI components.
 */

#include "hector_recorder/terminal_ui.hpp"
#include "hector_recorder/service_handlers.h"
#include "rclcpp/rclcpp.hpp"
#include "rosbag2_cpp/writers/sequential_writer.hpp"
#include "rosbag2_storage/storage_options.hpp"
#include "rosbag2_transport/record_options.hpp"
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fmt/chrono.h>
#include <fmt/core.h>
#include <memory>
#include <mutex>
#include <ncurses.h>
#include <string>
#include <vector>

using namespace std::chrono_literals;
using namespace hector_recorder;

namespace
{
inline int interior_width( WINDOW *win ) { return getmaxx( win ) - 2; }

constexpr int kColumnGap = 3;
inline int sep_offset() { return ( kColumnGap / 2 ) + 1; }

// Tablewidth from column widths + gaps (kColumnGap per gap) + trailing '---' (3)
inline int compute_table_width( const std::vector<int> &widths, size_t ncols )
{
  int sum = 0;
  for ( int w : widths ) sum += w;
  int gaps = ( ncols > 0 ) ? static_cast<int>( ncols - 1 ) * kColumnGap : 0;
  int trailing = 3; // last '---' for last column
  return sum + gaps + trailing;
}

// Clip with "..." at the end if truncated
inline std::string clip_with_ellipsis( const std::string &s, int width )
{
  if ( width <= 0 )
    return "";
  if ( (int)s.size() <= width )
    return s;
  if ( width <= 3 )
    return std::string( std::max( 0, width ), '.' );
  return s.substr( 0, width - 3 ) + "...";
}

// Global sort state (1-based column index). Default: sort by Size (column 5) desc
std::atomic<int> g_sort_column{ 5 };
std::atomic<bool> g_sort_desc{ true };

} // namespace

TerminalUI::TerminalUI( const CustomOptions &custom_options,
                        const rosbag2_storage::StorageOptions &storage_options,
                        const rosbag2_transport::RecordOptions &record_options )
    : Node( custom_options.node_name ), custom_options_( custom_options ),
      raw_output_uri_( storage_options.uri ),
      config_path_( custom_options.config_path ),
      publish_status_( custom_options.publish_status ),
      throttle_configs_( custom_options.topic_throttle )
{
  storage_options_ = storage_options;
  record_options_ = record_options;

  initializeRecorder();
  initializeUI();

  ui_refresh_timer_ = this->create_wall_timer( 100ms, [this]() { this->updateUI(); } );
  if ( publish_status_ ) {
    status_pub_ = this->create_publisher<hector_recorder_msgs::msg::RecorderStatus>(
        custom_options.status_topic, 10 );
    status_pub_timer_ = this->create_wall_timer( 1s, [this]() { this->publishRecorderStatus(); } );
  }

  initializeServices();
  startRecording();
}

TerminalUI::~TerminalUI()
{
  stopRecording();
  cleanupUI();
}

void TerminalUI::initializeRecorder()
{
  auto writer_impl = std::make_unique<rosbag2_cpp::writers::SequentialWriter>();
  auto writer = std::make_shared<rosbag2_cpp::Writer>( std::move( writer_impl ) );
  recorder_ = std::make_unique<RecorderImpl>( this, writer, storage_options_, record_options_,
                                              throttle_configs_ );
}

void TerminalUI::initializeUI()
{
  if ( initscr() == nullptr ) {
    throw std::runtime_error( "Error initializing ncurses. Terminal may not support it." );
  }
  cbreak();
  noecho();
  curs_set( 0 );
  start_color();

  use_default_colors();

  init_pair( 1, COLOR_GREEN, -1 );
  init_pair( 2, COLOR_RED, -1 );
  init_pair( 3, COLOR_YELLOW, -1 );
  init_pair( 4, COLOR_CYAN, -1 ); // throttled topics

  int height, width;
  getmaxyx( stdscr, height, width );

  int general_info_height = 3; // Placeholder for general info height, dynamically adjusted later
  generalInfoWin_ = newwin( general_info_height, width, 0, 0 );

  // Remaining height for tableWin_
  int table_height = height - general_info_height;
  tableWin_ = newwin( table_height, width, general_info_height, 0 );

  // enable non-blocking input and function keys
  nodelay( tableWin_, TRUE );
  keypad( tableWin_, TRUE );

  scrollok( tableWin_, true );

  // Draw borders for all windows
  for ( auto win : { generalInfoWin_, tableWin_ } ) {
    box( win, 0, 0 );
    wrefresh( win );
  }
}

void TerminalUI::cleanupUI()
{
  delwin( generalInfoWin_ );
  delwin( tableWin_ );
  endwin();
}

void TerminalUI::startRecording()
{
  if ( !recorder_ ) {
    RCLCPP_ERROR( this->get_logger(), "Recorder is not initialized. Cannot start recording." );
    return;
  }
  recorder_->record();
  RCLCPP_INFO( this->get_logger(), "Recording started." );
}

void TerminalUI::stopRecording()
{
  if ( recorder_ ) {
    recorder_->stop();
    RCLCPP_INFO( this->get_logger(), "Recording stopped." );
  }
}

void TerminalUI::updateUI()
{
  std::lock_guard<std::mutex> lock( data_mutex_ );

  // Handle user input for sorting
  int ch = wgetch( tableWin_ );
  if ( ch != ERR ) {
    if ( ch >= '1' && ch <= '8' ) {
      const int col = ch - '0';
      const int prev = g_sort_column.load();
      if ( prev != col ) {
        g_sort_column.store( col );
        g_sort_desc.store( ( col == 1 || col == 6 ) ? false : true );
      } else {
        g_sort_desc.store( !g_sort_desc.load() );
      }
    }
  }

  if ( !recorder_ ) {
    werase( generalInfoWin_ );
    box( generalInfoWin_, 0, 0 );
    mvwprintw( generalInfoWin_, 1, 1, "Recorder not initialized." );
    wrefresh( generalInfoWin_ );
    return;
  }

  updateGeneralInfo();

  // Dynamically adjust the size of tableWin_ based on the terminal size
  int general_info_height, general_info_width;
  getmaxyx( generalInfoWin_, general_info_height, general_info_width );
  int terminal_height, terminal_width;
  getmaxyx( stdscr, terminal_height, terminal_width );
  int table_height = terminal_height - general_info_height;
  if ( table_height > 0 ) {
    wresize( tableWin_, table_height, terminal_width );
    mvwin( tableWin_, general_info_height, 0 );
  }

  updateTable();
}

void TerminalUI::updateGeneralInfo()
{
  std::vector<std::string> lines;
  const std::string abs_uri = resolveOutputUriToAbsolute( storage_options_.uri );
  lines.push_back( fmt::format( "Bagfile Path: {}", abs_uri ) );
  if ( !config_path_.empty() ) {
    lines.push_back( fmt::format( "Config Path: {}", config_path_ ) );
  }
  lines.push_back(
      fmt::format( "Duration: {} s | Size: {} / {} | Files: {}",
                   static_cast<int>( recorder_->get_bagfile_duration().seconds() ),
                   formatMemory( recorder_->get_bagfile_size() ),
                   formatMemory( std::filesystem::space( abs_uri ).available ),
                   recorder_->get_files().size() ) );

  // Calculate the required height based on the content
  int required_height = calculateRequiredLines( lines );

  // Update the height of the generalInfoWin_ if it has changed
  int current_height, current_width;
  getmaxyx( generalInfoWin_, current_height, current_width );

  if ( current_height != required_height ) {
    wresize( generalInfoWin_, required_height, current_width );
    mvwin( generalInfoWin_, 0, 0 );
  }

  // Clear the old content and draw the border
  werase( generalInfoWin_ );
  box( generalInfoWin_, 0, 0 );

  const int inner = interior_width( generalInfoWin_ );

  if ( inner > 0 ) {
    // Write the content to the window, clipping if necessary
    for ( size_t i = 0; i < lines.size(); ++i ) {
      const std::string clipped = clip_with_ellipsis( lines[i], inner );
      mvwprintw( generalInfoWin_, static_cast<int>( i ) + 1, 1, "%-*s", inner, clipped.c_str() );
    }
  }

  // Refresh the window to display the new content
  wrefresh( generalInfoWin_ );
}

void TerminalUI::updateTable()
{
  werase( tableWin_ );
  box( tableWin_, 0, 0 );

  const auto &topics_info = recorder_->get_topics_info();
  max_width_ = getmaxx( tableWin_ );
  ui_topics_max_length_ = static_cast<int>( max_width_ * 0.3 );
  ui_topics_type_max_length_ = static_cast<int>( max_width_ * 0.2 );
  row_ = 1;

  if ( topics_info.empty() ) {
    mvwprintw( tableWin_, row_++, 1, "No topics or services selected." );
  } else {
    // Sort Topics by bandwidth, name, and frequency
    sorted_topics_ = sortTopics( topics_info );

    // Topic, Msg, Freq, Bandwidth, Size, Type, Pub, QoS
    headers_ = { "Topic", "Msgs", "Freq", "Bandwidth", "Size", "Type", "Pub", "QoS" };
    column_widths_.resize( headers_.size(), 0 );
    for ( size_t i = 0; i < headers_.size(); ++i ) { column_widths_[i] = headers_[i].size(); }

    // Adjust ColumnWidths and ensure Table fits the maximum width of the terminal
    adjustColumnWidths();

    renderTable();
  }

  wrefresh( tableWin_ );
}

std::vector<std::pair<std::string, TopicInformation>>
TerminalUI::sortTopics( const std::unordered_map<std::string, TopicInformation> &topics_info )
{
  std::vector<std::pair<std::string, TopicInformation>> sorted_topics( topics_info.begin(),
                                                                       topics_info.end() );

  // Capture current sort state once
  int sort_col = g_sort_column.load(); // 1..8
  bool sort_desc = g_sort_desc.load();

  std::sort( sorted_topics.begin(), sorted_topics.end(),
             [sort_col, sort_desc]( const auto &a, const auto &b ) {
               const auto &A = a.second;
               const auto &B = b.second;

               auto cmp_str = [&]( const std::string &x, const std::string &y ) {
                 if ( x == y )
                   return 0;
                 return ( x < y ) ? -1 : 1;
               };
               auto cmp_uint64 = [&]( uint64_t x, uint64_t y ) {
                 if ( x == y )
                   return 0;
                 return ( x < y ) ? -1 : 1;
               };
               auto cmp_double = [&]( double x, double y ) {
                 if ( x == y )
                   return 0;
                 return ( x < y ) ? -1 : 1;
               };

               int order = 0;
               switch ( sort_col ) {
               case 1: // Topic name
                 order = cmp_str( a.first, b.first );
                 break;
               case 2: // Msgs (message_count)
                 order = cmp_uint64( A.message_count(), B.message_count() );
                 break;
               case 3: // Freq
                 order = cmp_double( A.mean_frequency(), B.mean_frequency() );
                 break;
               case 4: // Bandwidth
                 order = cmp_double( A.bandwidth(), B.bandwidth() );
                 break;
               case 5: // Size (bytes)
                 order = cmp_uint64( A.size(), B.size() );
                 break;
               case 6: // Type
                 order = cmp_str( A.topic_type(), B.topic_type() );
                 break;
               case 7: // Pub (publisher_count)
                 order = cmp_uint64( A.publisher_count(), B.publisher_count() );
                 break;
               case 8: // QoS (string)
                 order = cmp_str( A.qos_reliability(), B.qos_reliability() );
                 break;
               default:
                 // fallback: by size desc, name asc, freq desc
                 if ( A.size() != B.size() )
                   return A.size() > B.size();
                 if ( a.first != b.first )
                   return a.first < b.first;
                 return A.mean_frequency() > B.mean_frequency();
               }

               if ( order == 0 ) {
                 if ( A.size() != B.size() )
                   return A.size() > B.size();
                 if ( a.first != b.first )
                   return a.first < b.first;
                 return A.mean_frequency() > B.mean_frequency();
               }

               if ( sort_desc )
                 return order > 0;
               else
                 return order < 0;
             } );

  return sorted_topics;
}

void TerminalUI::adjustColumnWidths()
{
  auto updateColumnWidth = [&]( size_t index, int value, int max_length = INT_MAX ) {
    column_widths_[index] = std::min( std::max( column_widths_[index], value ), max_length );
  };

  size_t longest_topic_name = column_widths_[0];
  size_t longest_topic_type = ( column_widths_.size() > 5 ) ? column_widths_[5] : 0;

  for ( const auto &topic : sorted_topics_ ) {
    const auto &info = topic.second;

    // Update longest topic name
    longest_topic_name = std::max( longest_topic_name, topic.first.size() );

    // Update topic name
    updateColumnWidth( 0, static_cast<int>( topic.first.size() ), ui_topics_max_length_ );

    // Update message count
    updateColumnWidth( 1, static_cast<int>( std::to_string( info.message_count() ).size() ) );

    // Update frequency
    updateColumnWidth( 2, static_cast<int>( rateToString( info.mean_frequency() ).size() ) );

    // Update bandwidth
    updateColumnWidth( 3, static_cast<int>( bandwidthToString( info.bandwidth() ).size() ) );

    // Update size
    updateColumnWidth( 4, static_cast<int>( formatMemory( info.size() ).size() ) );

    // Update topic type
    longest_topic_type = std::max( longest_topic_type, info.topic_type().size() );
    updateColumnWidth( 5, static_cast<int>( info.topic_type().size() ), ui_topics_type_max_length_ );

    // Update publisher count
    updateColumnWidth( 6, static_cast<int>( std::to_string( info.publisher_count() ).size() ) );

    // Update QoS
    updateColumnWidth( 7, static_cast<int>( info.qos_reliability().size() ) );
  }

  // Calculate total width
  total_width_ = compute_table_width( column_widths_, headers_.size() );

  // Ensure table fits within the maximum width of the terminal window
  const int inner = interior_width( tableWin_ );
  while ( total_width_ > inner && !headers_.empty() ) {
    headers_.pop_back();
    column_widths_.pop_back();
    total_width_ = compute_table_width( column_widths_, headers_.size() );
  }

  // Distribute remaining width
  distributeRemainingWidth( longest_topic_name, longest_topic_type );
}

void TerminalUI::distributeRemainingWidth( size_t longest_topic_name, size_t longest_topic_type )
{
  if ( headers_.empty() )
    return;

  const int inner = interior_width( tableWin_ );
  total_width_ = compute_table_width( column_widths_, headers_.size() );

  if ( total_width_ >= inner )
    return;

  int remaining_width = inner - total_width_;

  auto growUpTo = [&]( size_t idx, size_t longest_size, int budget, size_t &max_length ) -> int {
    int needed = static_cast<int>( longest_size ) - column_widths_[idx];
    int give = std::max( 0, std::min( needed, budget ) );
    column_widths_[idx] += give;
    max_length += give;
    return give;
  };

  bool need_name = column_widths_[0] < static_cast<int>( longest_topic_name );
  bool need_type = headers_.size() > 5 && column_widths_[5] < static_cast<int>( longest_topic_type );

  if ( need_name && need_type ) {
    int give_name = remaining_width * 3 / 5;
    int used_name = growUpTo( 0, longest_topic_name, give_name, ui_topics_max_length_ );
    remaining_width -= used_name;

    int used_type = growUpTo( 5, longest_topic_type, remaining_width, ui_topics_type_max_length_ );
    remaining_width -= used_type;
  } else if ( need_name ) {
    int used = growUpTo( 0, longest_topic_name, remaining_width, ui_topics_max_length_ );
    remaining_width -= used;
  } else if ( need_type ) {
    int used = growUpTo( 5, longest_topic_type, remaining_width, ui_topics_type_max_length_ );
    remaining_width -= used;
  }

  total_width_ = compute_table_width( column_widths_, headers_.size() );
}

void TerminalUI::renderTable()
{
  // Render Headers
  renderHeaders();

  // Render Separator Line
  renderSeperatorLine();

  // Render Topics
  for ( const auto &topic : sorted_topics_ ) { renderTopicRow( topic ); }
}

void TerminalUI::renderHeaders()
{
  for ( size_t i = 0, col = 1; i < headers_.size(); ++i ) {
    std::string label = headers_[i];
    int col_no = static_cast<int>( i ) + 1;
    const std::string to_print = clip_with_ellipsis( label, column_widths_[i] );

    // Draw header with green text and bold when it's the sort column
    if ( g_sort_column.load() == col_no ) {
      wattron( tableWin_, COLOR_PAIR( 1 ) | A_BOLD );
      mvwprintw( tableWin_, row_, col, "%-*s", column_widths_[i], to_print.c_str() );
      wattroff( tableWin_, COLOR_PAIR( 1 ) | A_BOLD );
    } else {
      wattron( tableWin_, COLOR_PAIR( 1 ) );
      mvwprintw( tableWin_, row_, col, "%-*s", column_widths_[i], to_print.c_str() );
      wattroff( tableWin_, COLOR_PAIR( 1 ) );
    }

    col += column_widths_[i];
    if ( i < headers_.size() - 1 ) {
      col += kColumnGap;
      mvwaddch( tableWin_, row_, col - sep_offset(), '|' );
    }
  }
  row_++;
}

void TerminalUI::renderSeperatorLine()
{
  const int inner = interior_width( tableWin_ );

  const int base_width = std::min( total_width_, inner );
  mvwhline( tableWin_, row_, 1, '-', base_width );

  // Add '+' as column separators
  for ( size_t i = 0, col = 1; i < headers_.size(); ++i ) {
    col += column_widths_[i];
    if ( i < headers_.size() - 1 ) {
      int plus_x = col + ( kColumnGap / 2 );
      if ( plus_x >= 1 && plus_x <= inner )
        mvwaddch( tableWin_, row_, plus_x, '+' );
      col += kColumnGap;
    }
  }

  row_++;
}

void TerminalUI::renderTopicRow( const std::pair<std::string, TopicInformation> &topic )
{
  const auto &info = topic.second;
  int col = 1;

  // Row coloring (foreground text only):
  // - red text if no publishers
  // - yellow text if there are publishers but no messages received yet
  int active_color_pair = 0;
  if ( info.publisher_count() == 0 ) {
    active_color_pair = 2; // red text
  } else if ( info.publisher_count() > 0 && info.message_count() == 0 ) {
    active_color_pair = 3; // yellow text
  }
  if ( active_color_pair != 0 ) {
    wattron( tableWin_, COLOR_PAIR( active_color_pair ) );
  }

  // Populate table columns
  // Topic, Msg, Freq, Bandwidth, Size, Type, Pub, QoS
  const std::vector<std::string> column_data = {
      clipString( topic.first, column_widths_[0] ),       // Topic name
      std::to_string( info.message_count() ),             // Message count
      rateToString( info.mean_frequency() ),              // Frequency
      bandwidthToString( info.bandwidth() ),              // Bandwidth
      formatMemory( info.size() ),                        // Size
      clipString( info.topic_type(), column_widths_[5] ), // Topic type
      std::to_string( info.publisher_count() ),           // Publisher count
      info.qos_reliability()                              // QoS
  };

  // Check if this topic is throttled and which column to highlight
  bool has_throttle = throttle_configs_.count( topic.first ) > 0;

  for ( size_t i = 0; i < headers_.size(); ++i ) {
    // Highlight only the relevant column: Freq (2) for MESSAGES, Bandwidth (3) for BYTES
    bool throttle_highlight =
        has_throttle &&
        ( ( throttle_configs_.at( topic.first ).type == ThrottleConfig::MESSAGES && i == 2 ) ||
          ( throttle_configs_.at( topic.first ).type == ThrottleConfig::BYTES && i == 3 ) );
    if ( throttle_highlight ) {
      wattron( tableWin_, COLOR_PAIR( 4 ) );
    }

    mvwprintw( tableWin_, row_, col, "%-*s", column_widths_[i], column_data[i].c_str() );

    if ( throttle_highlight ) {
      wattroff( tableWin_, COLOR_PAIR( 4 ) );
      // Re-apply row color if active
      if ( active_color_pair != 0 ) {
        wattron( tableWin_, COLOR_PAIR( active_color_pair ) );
      }
    }

    col += column_widths_[i];
    if ( i < headers_.size() - 1 ) {
      col += kColumnGap;
      mvwaddch( tableWin_, row_, col - sep_offset(), '|' );
    }
  }

  if ( active_color_pair != 0 ) {
    wattroff( tableWin_, COLOR_PAIR( active_color_pair ) );
  }

  row_++;
}

void TerminalUI::initializeServices()
{
  start_srv_ = this->create_service<hector_recorder_msgs::srv::StartRecording>(
      "~/start_recording",
      std::bind( &TerminalUI::onStartRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  stop_srv_ = this->create_service<hector_recorder_msgs::srv::StopRecording>(
      "~/stop_recording",
      std::bind( &TerminalUI::onStopRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  pause_srv_ = this->create_service<hector_recorder_msgs::srv::PauseRecording>(
      "~/pause_recording",
      std::bind( &TerminalUI::onPauseRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  resume_srv_ = this->create_service<hector_recorder_msgs::srv::ResumeRecording>(
      "~/resume_recording",
      std::bind( &TerminalUI::onResumeRecording, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  split_srv_ = this->create_service<hector_recorder_msgs::srv::SplitBag>(
      "~/split_bag",
      std::bind( &TerminalUI::onSplitBag, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  config_srv_ = this->create_service<hector_recorder_msgs::srv::ApplyConfig>(
      "~/apply_config",
      std::bind( &TerminalUI::onApplyConfig, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  save_config_srv_ = this->create_service<hector_recorder_msgs::srv::SaveConfig>(
      "~/save_config",
      std::bind( &TerminalUI::onSaveConfig, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  topics_srv_ = this->create_service<hector_recorder_msgs::srv::GetAvailableTopics>(
      "~/get_available_topics",
      std::bind( &TerminalUI::onGetAvailableTopics, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  services_srv_ = this->create_service<hector_recorder_msgs::srv::GetAvailableServices>(
      "~/get_available_services",
      std::bind( &TerminalUI::onGetAvailableServices, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  get_config_srv_ = this->create_service<hector_recorder_msgs::srv::GetConfig>(
      "~/get_config",
      std::bind( &TerminalUI::onGetConfig, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  get_info_srv_ = this->create_service<hector_recorder_msgs::srv::GetRecorderInfo>(
      "~/get_recorder_info",
      std::bind( &TerminalUI::onGetRecorderInfo, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  list_bags_srv_ = this->create_service<hector_recorder_msgs::srv::ListBags>(
      "~/list_bags",
      std::bind( &TerminalUI::onListBags, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  get_bag_details_srv_ = this->create_service<hector_recorder_msgs::srv::GetBagDetails>(
      "~/get_bag_details",
      std::bind( &TerminalUI::onGetBagDetails, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
  delete_bag_srv_ = this->create_service<hector_recorder_msgs::srv::DeleteBag>(
      "~/delete_bag",
      std::bind( &TerminalUI::onDeleteBag, this, std::placeholders::_1,
                 std::placeholders::_2 ) );
}

void TerminalUI::onStartRecording(
    const std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::StartRecording::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleStartRecording( recorder_, storage_options_, record_options_, custom_options_,
                        raw_output_uri_, request->output_dir, request->recorded_by, this,
                        response->success, response->message, response->bag_path );
}

void TerminalUI::onStopRecording(
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

void TerminalUI::onPauseRecording(
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

void TerminalUI::onResumeRecording(
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

void TerminalUI::onSplitBag(
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

void TerminalUI::onApplyConfig(
    const std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::ApplyConfig::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleApplyConfig( recorder_, custom_options_, record_options_, storage_options_,
                     raw_output_uri_, request->config_yaml, request->restart, this,
                     response->success, response->message, response->active_config_yaml );
  // Update TUI-local copies that mirror custom_options_
  throttle_configs_ = custom_options_.topic_throttle;
  config_path_ = custom_options_.config_path;
}

void TerminalUI::onSaveConfig(
    const std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::SaveConfig::Response> response )
{
  handleSaveConfig( request->config_yaml, request->file_path, response->success,
                    response->message );
  if ( response->success ) {
    RCLCPP_INFO( this->get_logger(), "Config saved to %s", request->file_path.c_str() );
  }
}

void TerminalUI::onGetAvailableTopics(
    const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetAvailableTopics::Response> response )
{
  handleGetAvailableTopics( this, response->topics, response->types );
}

void TerminalUI::onGetAvailableServices(
    const std::shared_ptr<hector_recorder_msgs::srv::GetAvailableServices::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetAvailableServices::Response> response )
{
  handleGetAvailableServices( this, response->services, response->types );
}

void TerminalUI::onGetConfig(
    const std::shared_ptr<hector_recorder_msgs::srv::GetConfig::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetConfig::Response> response )
{
  std::lock_guard<std::mutex> lock( data_mutex_ );
  handleGetConfig( custom_options_, record_options_, storage_options_, raw_output_uri_,
                   response->config_yaml );
}

void TerminalUI::onGetRecorderInfo(
    const std::shared_ptr<hector_recorder_msgs::srv::GetRecorderInfo::Request>,
    std::shared_ptr<hector_recorder_msgs::srv::GetRecorderInfo::Response> response )
{
  handleGetRecorderInfo( custom_options_, response->hostname, response->recorded_by,
                         response->config_path );
}

void TerminalUI::onListBags(
    const std::shared_ptr<hector_recorder_msgs::srv::ListBags::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::ListBags::Response> response )
{
  std::string path = request->path;
  if ( path.empty() ) {
    std::lock_guard<std::mutex> lock( data_mutex_ );
    // storage_options_.uri points to the current bag directory (e.g. .../bags/rosbag2_<stamp>).
    // For listing, we want its parent (the directory containing all bags).
    path = fs::path( storage_options_.uri ).parent_path().string();
  }
  handleListBags( path, storage_options_, response->bags, response->success, response->message );
}

void TerminalUI::onGetBagDetails(
    const std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::GetBagDetails::Response> response )
{
  handleGetBagDetails( request->bag_path, response->info, response->topics, response->success,
                       response->message );
}

void TerminalUI::onDeleteBag(
    const std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Request> request,
    std::shared_ptr<hector_recorder_msgs::srv::DeleteBag::Response> response )
{
  handleDeleteBag( request->bag_path, request->confirm, response->success, response->message );
  if ( response->success ) {
    RCLCPP_INFO( this->get_logger(), "Deleted bag: %s", request->bag_path.c_str() );
  }
}

void TerminalUI::publishRecorderStatus()
{
  hector_recorder_msgs::msg::RecorderStatus status_msg;
  {
    std::lock_guard<std::mutex> lock( data_mutex_ );
    fillRecorderStatus( status_msg, recorder_.get(), custom_options_, storage_options_, this );
  }
  status_pub_->publish( status_msg );
}
