#ifndef HECTOR_RECORDER_TOPIC_INFORMATION_HPP
#define HECTOR_RECORDER_TOPIC_INFORMATION_HPP

#include <boost/accumulators/accumulators.hpp>
#include <boost/accumulators/statistics/rolling_mean.hpp>
#include <boost/accumulators/statistics/stats.hpp>

#include <chrono>
#include <string>

namespace hector_recorder
{

namespace ba = boost::accumulators;

/// If no message is received for this duration, frequency and bandwidth report zero.
constexpr double kStaleDataTimeoutSec = 3.0;

class TopicInformation
{
public:
  TopicInformation()
      : time_intervals_acc_( ba::tag::rolling_window::window_size = 100 ),
        size_acc_( ba::tag::rolling_window::window_size = 100 ),
        last_msg_stamp_( std::chrono::nanoseconds::zero() )
  {
  }

  void update_statistics( const std::chrono::nanoseconds &timestamp, size_t size )
  {
    if ( last_msg_stamp_ != std::chrono::nanoseconds::zero() ) {
      time_intervals_acc_( timestamp - last_msg_stamp_ );
    }
    last_msg_stamp_ = timestamp;
    last_update_ = std::chrono::steady_clock::now();

    size_acc_( size );
    size_ += size;

    message_count_++;
  }

  void update_publisher_info( const std::string &type, int count, const std::string &qos_profile )
  {
    topic_type_ = type;
    publisher_count_ = count;
    qos_ = qos_profile;
  }

  const std::string &topic_type() const { return topic_type_; }

  int publisher_count() const { return publisher_count_; }

  const std::string &qos_reliability() const { return qos_; }

  size_t message_count() const { return message_count_; }

  size_t size() const { return size_; }

  double mean_frequency() const
  {
    if ( message_count_ < 2 || isDataStale() ) {
      return 0.0;
    }

    return 1.0 / ( ba::rolling_mean( time_intervals_acc_ ).count() / 1e9 ); // nanoseconds to seconds
  }

  size_t bandwidth() const
  {
    if ( message_count_ < 2 || isDataStale() ) {
      return 0;
    }

    double freq = mean_frequency();
    return ba::rolling_mean( size_acc_ ) * freq;
  }

private:
  bool isDataStale() const
  {
    auto elapsed = std::chrono::steady_clock::now() - last_update_;
    return std::chrono::duration_cast<std::chrono::seconds>( elapsed ).count() > kStaleDataTimeoutSec;
  }

  size_t message_count_ = 0;
  size_t size_ = 0;
  std::string topic_type_;
  int publisher_count_ = 0;
  std::string qos_;
  ba::accumulator_set<std::chrono::nanoseconds, ba::stats<ba::tag::rolling_mean>> time_intervals_acc_;
  ba::accumulator_set<size_t, ba::stats<ba::tag::rolling_mean>> size_acc_;
  std::chrono::nanoseconds last_msg_stamp_;
  std::chrono::time_point<std::chrono::steady_clock> last_update_;
};

} // namespace hector_recorder

#endif // HECTOR_RECORDER_TOPIC_INFORMATION_HPP
