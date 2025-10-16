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
#include "hector_recorder/utils.h"
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
// Innerwidth (without borders)
inline int interior_width( WINDOW *win ) { return getmaxx( win ) - 2; }

// Tablewidth from column widths + gaps (7 per gap) + trailing '---' (3)
inline int compute_table_width( const std::vector<int> &widths, size_t ncols )
{
  int sum = 0;
  for ( int w : widths ) sum += w;
  int gaps = ( ncols > 0 ) ? static_cast<int>( ncols - 1 ) * 7 : 0;
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
} // namespace

TerminalUI::TerminalUI( const CustomOptions &custom_options,
                        const rosbag2_storage::StorageOptions &storage_options,
                        const rosbag2_transport::RecordOptions &record_options )
    : Node( custom_options.node_name ), config_path_( custom_options.config_path ),
      publish_status_( custom_options.publish_status )
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

  startRecording();
}

TerminalUI::~TerminalUI()
{
  stopRecording();
  cleanupUI();
}

void TerminalUI::initializeRecorder()
{
  if ( initscr() == nullptr ) {
    throw std::runtime_error( "Error initializing ncurses. Terminal may not support it." );
  }
  cbreak();
  auto writer_impl = std::make_unique<rosbag2_cpp::writers::SequentialWriter>();
  auto writer = std::make_shared<rosbag2_cpp::Writer>( std::move( writer_impl ) );
  recorder_ = std::make_unique<RecorderImpl>( this, writer, storage_options_, record_options_ );
}

void TerminalUI::initializeUI()
{
  initscr();
  cbreak();
  noecho();
  curs_set( 0 );
  start_color();

  use_default_colors();

  init_pair( 1, COLOR_GREEN, -1 );
  init_pair( 2, COLOR_RED, -1 );
  init_pair( 3, COLOR_YELLOW, -1 );

  int height, width;
  getmaxyx( stdscr, height, width );

  int general_info_height = 3; // Placeholder for general info height, dynamically adjusted later
  generalInfoWin_ = newwin( general_info_height, width, 0, 0 );

  // Remaining height for tableWin_
  int table_height = height - general_info_height;
  tableWin_ = newwin( table_height, width, general_info_height, 0 );

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
  lines.push_back(
      fmt::format( "Bagfile Path: {}", resolveOutputUriToAbsolute( storage_options_.uri ) ) );
  if ( !config_path_.empty() ) {
    lines.push_back( fmt::format( "Config Path: {}", config_path_ ) );
  }
  lines.push_back(
      fmt::format( "Duration: {} s | Size: {} | Files: {} | Free Space: {}",
                   static_cast<int>( recorder_->get_bagfile_duration().seconds() ),
                   formatMemory( recorder_->get_bagfile_size() ), recorder_->get_files().size(),
                   formatMemory( std::filesystem::space( storage_options_.uri ).available ) ) );

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
  ui_topics_max_length_ =
      static_cast<int>( max_width_ * 0.3 ); // topic name should not exceed 30% of the window width
  ui_topics_type_max_length_ =
      static_cast<int>( max_width_ * 0.2 ); // topic type should not exceed 20% of the window width
  row_ = 1;

  if ( topics_info.empty() ) {
    mvwprintw( tableWin_, row_++, 1, "No topics or services selected." );
  } else {
    // Sort Topics by bandwidth, name, and frequency
    sorted_topics_ = sortTopics( topics_info );

    // Prepare headers and column widths
    headers_ = { "Topic", "Msgs", "Freq", "Type", "Bandwidth", "Pub", "QoS", "Size" };
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
  // Sort the vector based on bandwidth (desc), name (asc), and frequency (desc)
  std::sort( sorted_topics.begin(), sorted_topics.end(), []( const auto &a, const auto &b ) {
    if ( a.second.bandwidth() != b.second.bandwidth() ) {
      return a.second.bandwidth() > b.second.bandwidth();
    }
    if ( a.first != b.first ) {
      return a.first < b.first;
    }
    return a.second.mean_frequency() > b.second.mean_frequency();
  } );
  return sorted_topics;
}

void TerminalUI::adjustColumnWidths()
{
  auto updateColumnWidth = [&]( size_t index, int value, int max_length = INT_MAX ) {
    column_widths_[index] = std::min( std::max( column_widths_[index], value ), max_length );
  };

  size_t longest_topic_name = column_widths_[0];
  size_t longest_topic_type = column_widths_[3];

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

    // Update topic type
    longest_topic_type = std::max( longest_topic_type, info.topic_type().size() );
    updateColumnWidth( 3, static_cast<int>( info.topic_type().size() ), ui_topics_type_max_length_ );

    // Update bandwidth
    updateColumnWidth( 4, static_cast<int>( bandwidthToString( info.bandwidth() ).size() ) );

    // Update publisher count
    updateColumnWidth( 5, static_cast<int>( std::to_string( info.publisher_count() ).size() ) );

    // Update QoS
    updateColumnWidth( 6, static_cast<int>( info.qos_reliability().size() ) );

    // Update memory size
    updateColumnWidth( 7, static_cast<int>( formatMemory( info.size() ).size() ) );
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
  bool need_type = headers_.size() > 3 && column_widths_[3] < static_cast<int>( longest_topic_type );

  if ( need_name && need_type ) {
    int give_name = remaining_width * 3 / 5;
    int used_name = growUpTo( 0, longest_topic_name, give_name, ui_topics_max_length_ );
    remaining_width -= used_name;

    int used_type = growUpTo( 3, longest_topic_type, remaining_width, ui_topics_type_max_length_ );
    remaining_width -= used_type;
  } else if ( need_name ) {
    int used = growUpTo( 0, longest_topic_name, remaining_width, ui_topics_max_length_ );
    remaining_width -= used;
  } else if ( need_type ) {
    int used = growUpTo( 3, longest_topic_type, remaining_width, ui_topics_type_max_length_ );
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
    mvwprintw( tableWin_, row_, col, "%-*s", column_widths_[i], headers_[i].c_str() );
    col += column_widths_[i];
    if ( i < headers_.size() - 1 ) {
      col += 7; // 3 spaces + '|' + 3 spaces
      mvwaddch( tableWin_, row_, col - 4, '|' );
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
      int plus_x = col + 3;
      if ( plus_x >= 1 && plus_x <= inner )
        mvwaddch( tableWin_, row_, plus_x, '+' );
      col += 7;
    }
  }

  row_++;
}

void TerminalUI::renderTopicRow( const std::pair<std::string, TopicInformation> &topic )
{
  const auto &info = topic.second;
  int col = 1;

  // Highlight row if no publishers
  if ( info.publisher_count() == 0 ) {
    wattron( tableWin_, COLOR_PAIR( 2 ) ); // Activate red color for unpublished topics
  }

  // Populate table columns
  const std::vector<std::string> column_data = {
      clipString( topic.first, column_widths_[0] ),       // Topic name
      std::to_string( info.message_count() ),             // Message count
      rateToString( info.mean_frequency() ),              // Frequency
      clipString( info.topic_type(), column_widths_[3] ), // Topic type
      bandwidthToString( info.bandwidth() ),              // Bandwidth
      std::to_string( info.publisher_count() ),           // Publisher count
      info.qos_reliability(),                             // QoS
      formatMemory( info.size() )                         // Memory size
  };

  for ( size_t i = 0; i < headers_.size(); ++i ) {
    mvwprintw( tableWin_, row_, col, "%-*s", column_widths_[i], column_data[i].c_str() );
    col += column_widths_[i] + 7; // Move to next column
    if ( i < headers_.size() - 1 ) {
      mvwaddch( tableWin_, row_, col - 4, '|' ); // Add column separator
    }
  }

  if ( info.publisher_count() == 0 ) {
    wattroff( tableWin_, COLOR_PAIR( 2 ) ); // Deactivate red color
  }

  row_++; // Move to next row
}

void TerminalUI::publishRecorderStatus()
{
  if ( !recorder_ ) {
    return;
  }

  std::lock_guard<std::mutex> lock( data_mutex_ );

  hector_recorder_msgs::msg::RecorderStatus status_msg;
  status_msg.output_dir = storage_options_.uri;
  status_msg.config_path = config_path_;
  status_msg.files = recorder_->get_files();
  status_msg.duration = recorder_->get_bagfile_duration();
  status_msg.size = recorder_->get_bagfile_size();
  for ( const auto &topic_info : recorder_->get_topics_info() ) {
    hector_recorder_msgs::msg::TopicInfo topic_msg;
    topic_msg.topic = topic_info.first;
    topic_msg.msg_count = topic_info.second.message_count();
    topic_msg.frequency = topic_info.second.mean_frequency();
    topic_msg.bandwidth = topic_info.second.bandwidth();
    topic_msg.size = topic_info.second.size();
    status_msg.topics.push_back( topic_msg );
  }

  status_pub_->publish( status_msg );
}
