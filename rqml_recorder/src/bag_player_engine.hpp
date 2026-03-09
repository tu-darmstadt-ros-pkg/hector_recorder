#ifndef RQML_RECORDER_BAG_PLAYER_ENGINE_HPP
#define RQML_RECORDER_BAG_PLAYER_ENGINE_HPP

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include <rclcpp/generic_publisher.hpp>
#include <rclcpp/node.hpp>
#include <rclcpp/publisher.hpp>
#include <rosbag2_cpp/reader.hpp>
#include <rosbag2_storage/bag_metadata.hpp>
#include <rosbag2_storage/serialized_bag_message.hpp>
#include <rosgraph_msgs/msg/clock.hpp>

/**
 * Embedded rosbag2 playback engine exposed to QML.
 * Uses rosbag2_cpp::Reader for reading and rclcpp::GenericPublisher for publishing.
 * Timing is driven by a QTimer integrated with the Qt event loop.
 */
class BagPlayerEngine : public QObject
{
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY( QString bagPath READ bagPath NOTIFY bagPathChanged )
  Q_PROPERTY( QString bagName READ bagName NOTIFY bagPathChanged )
  Q_PROPERTY( QString state READ state NOTIFY stateChanged )
  Q_PROPERTY( double rate READ rate WRITE setRate NOTIFY rateChanged )
  Q_PROPERTY( bool looping READ looping WRITE setLooping NOTIFY loopingChanged )
  Q_PROPERTY( double duration READ duration NOTIFY metadataChanged )
  Q_PROPERTY( double currentTime READ currentTime NOTIFY progressChanged )
  Q_PROPERTY( double progress READ progress NOTIFY progressChanged )
  Q_PROPERTY( bool clockEnabled READ clockEnabled WRITE setClockEnabled NOTIFY clockEnabledChanged )
  Q_PROPERTY( double clockFrequency READ clockFrequency WRITE setClockFrequency NOTIFY
                  clockFrequencyChanged )
  Q_PROPERTY( int topicCount READ topicCount NOTIFY metadataChanged )
  Q_PROPERTY( int messageCount READ messageCount NOTIFY metadataChanged )
  Q_PROPERTY( QStringList topicList READ topicList NOTIFY metadataChanged )
  Q_PROPERTY( QString errorMessage READ errorMessage NOTIFY errorMessageChanged )

public:
  explicit BagPlayerEngine( QObject *parent = nullptr );
  ~BagPlayerEngine() override;

  // Property getters
  QString bagPath() const;
  QString bagName() const;
  QString state() const;
  double rate() const;
  bool looping() const;
  double duration() const;
  double currentTime() const;
  double progress() const;
  bool clockEnabled() const;
  double clockFrequency() const;
  int topicCount() const;
  int messageCount() const;
  QStringList topicList() const;
  QString errorMessage() const;

  // Property setters
  void setRate( double rate );
  void setLooping( bool looping );
  void setClockEnabled( bool enabled );
  void setClockFrequency( double hz );

  /// Load a bag and read its metadata. Does not start playback.
  Q_INVOKABLE void load( const QString &bagPath );

  /// Start or resume playback. topicFilter: empty = all topics.
  Q_INVOKABLE void play( const QStringList &topicFilter = {} );

  /// Pause playback (keeps position).
  Q_INVOKABLE void pause();

  /// Resume from paused state.
  Q_INVOKABLE void resume();

  /// Stop playback and reset to beginning.
  Q_INVOKABLE void stop();

  /// Seek to a position in seconds from bag start.
  Q_INVOKABLE void seek( double seconds );

  /// Play a single next message (while paused). Returns true if a message was played.
  Q_INVOKABLE bool stepForward();

  /// Enable or disable publishing for a specific topic during playback.
  Q_INVOKABLE void setTopicEnabled( const QString &topic, bool enabled );

signals:
  void bagPathChanged();
  void stateChanged();
  void rateChanged();
  void loopingChanged();
  void metadataChanged();
  void progressChanged();
  void clockEnabledChanged();
  void clockFrequencyChanged();
  void errorMessageChanged();
  void playbackFinished();

private:
  void setState( const QString &s );
  void setError( const QString &msg );
  void onPlaybackTick();
  void onClockTick();
  bool publishNextMessage();
  void createPublishers( const QStringList &topicFilter );
  void destroyPublishers();
  void ensureNode();
  void publishClock( rcutils_time_point_value_t bag_time_ns );
  void reopenAndSeek( rcutils_time_point_value_t target_ns );

  // State
  QString bagPath_;
  QString bagName_;
  QString state_ = "idle";
  double rate_ = 1.0;
  bool looping_ = false;
  bool clockEnabled_ = false;
  double clockFrequency_ = 100.0;
  QString errorMessage_;

  // Bag metadata
  double duration_ = 0.0;
  rcutils_time_point_value_t bagStartNs_ = 0;
  rcutils_time_point_value_t bagEndNs_ = 0;
  int topicCount_ = 0;
  int messageCount_ = 0;
  QStringList topicList_;

  // Re-entrancy guard
  bool stopping_ = false;

  // Playback state
  rcutils_time_point_value_t currentBagTimeNs_ = 0;
  std::chrono::steady_clock::time_point wallTimeAtLastMsg_;
  rcutils_time_point_value_t lastMsgBagTimeNs_ = 0;
  bool firstMessage_ = true;
  std::shared_ptr<rosbag2_storage::SerializedBagMessage> pendingMsg_;
  rosbag2_storage::StorageFilter activeFilter_;
  std::unordered_set<std::string> disabledTopics_;

  // Reader
  std::unique_ptr<rosbag2_cpp::Reader> reader_;

  // ROS 2 node and publishers
  rclcpp::Node::SharedPtr node_;
  std::unordered_map<std::string, rclcpp::GenericPublisher::SharedPtr> publishers_;
  rclcpp::Publisher<rosgraph_msgs::msg::Clock>::SharedPtr clockPublisher_;

  // Timers
  QTimer playbackTimer_;
  QTimer clockTimer_;
};

#endif // RQML_RECORDER_BAG_PLAYER_ENGINE_HPP
