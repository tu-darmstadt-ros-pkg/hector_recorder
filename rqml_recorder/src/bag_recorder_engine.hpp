#ifndef RQML_RECORDER_BAG_RECORDER_ENGINE_HPP
#define RQML_RECORDER_BAG_RECORDER_ENGINE_HPP

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include <rclcpp/context.hpp>
#include <rclcpp/executors/single_threaded_executor.hpp>
#include <rclcpp/generic_subscription.hpp>
#include <rclcpp/node.hpp>
#include <rclcpp/serialized_message.hpp>
#include <rosbag2_cpp/writer.hpp>

/**
 * Embedded rosbag2 recording engine exposed to QML.
 * Uses rosbag2_cpp::Writer for writing and rclcpp::GenericSubscription
 * for receiving serialized messages. Statistics are updated via QTimer.
 */
class BagRecorderEngine : public QObject
{
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY( QString state READ state NOTIFY stateChanged )
  Q_PROPERTY( QString outputDir READ outputDir WRITE setOutputDir NOTIFY outputDirChanged )
  Q_PROPERTY( QString recordedBy READ recordedBy WRITE setRecordedBy NOTIFY recordedByChanged )
  Q_PROPERTY( QString currentBagPath READ currentBagPath NOTIFY currentBagPathChanged )
  Q_PROPERTY( double duration READ duration NOTIFY statsChanged )
  Q_PROPERTY( double totalSize READ totalSize NOTIFY statsChanged )
  Q_PROPERTY( int messageCount READ messageCount NOTIFY statsChanged )
  Q_PROPERTY( int topicCount READ topicCount NOTIFY statsChanged )
  Q_PROPERTY( QString errorMessage READ errorMessage NOTIFY errorMessageChanged )

public:
  explicit BagRecorderEngine( QObject *parent = nullptr );
  ~BagRecorderEngine() override;

  // Property getters
  QString state() const;
  QString outputDir() const;
  QString recordedBy() const;
  QString currentBagPath() const;
  double duration() const;
  double totalSize() const;
  int messageCount() const;
  int topicCount() const;
  QString errorMessage() const;

  // Property setters
  void setOutputDir( const QString &dir );
  void setRecordedBy( const QString &name );

  /// Query all topics currently available on the ROS graph.
  /// Returns [{name, type, publisherCount}].
  Q_INVOKABLE QVariantList discoverTopics();

  /// Start recording the given topics to outputDir.
  Q_INVOKABLE void startRecording( const QStringList &topics, const QString &outputDir = {} );

  /// Stop recording and close the bag.
  Q_INVOKABLE void stopRecording();

  /// Pause recording (messages are discarded while paused).
  Q_INVOKABLE void pauseRecording();

  /// Resume recording.
  Q_INVOKABLE void resumeRecording();

  /// Split the current bag file.
  Q_INVOKABLE void splitBag();

  /// Get per-topic statistics as QVariantList.
  /// Each entry: {topic, type, msgCount, frequency, size, bandwidth}.
  Q_INVOKABLE QVariantList getTopicStats();

signals:
  void stateChanged();
  void outputDirChanged();
  void recordedByChanged();
  void currentBagPathChanged();
  void statsChanged();
  void errorMessageChanged();
  void recordingFinished( const QString &bagPath );

private:
  void setState( const QString &s );
  void setError( const QString &msg );
  void ensureNode();
  void shutdownNode();
  void destroySubscriptions();
  void onStatsTick();

  // Per-topic statistics (mutex-protected)
  struct TopicStats {
    std::string type;
    int publisherCount = 0;
    int64_t msgCount = 0;
    int64_t totalBytes = 0;
    // Sliding window for frequency/bandwidth
    std::chrono::steady_clock::time_point windowStart;
    int64_t windowMsgs = 0;
    int64_t windowBytes = 0;
    double frequency = 0.0;
    double bandwidth = 0.0;
  };

  // State
  QString state_ = "idle";
  QString outputDir_;
  QString recordedBy_;
  QString currentBagPath_;
  QString errorMessage_;

  // Recording state
  std::atomic<bool> paused_{false};
  std::atomic<bool> stopping_{false};
  std::chrono::steady_clock::time_point recordingStart_;

  // Writer
  std::unique_ptr<rosbag2_cpp::Writer> writer_;
  std::mutex writerMutex_;

  // Statistics
  std::mutex statsMutex_;
  std::unordered_map<std::string, TopicStats> topicStats_;
  int totalMessageCount_ = 0;
  double totalSize_ = 0.0;

  // ROS 2 node, executor thread, and subscriptions
  std::shared_ptr<rclcpp::Context> ctx_;
  rclcpp::Node::SharedPtr node_;
  std::unique_ptr<rclcpp::executors::SingleThreadedExecutor> executor_;
  std::thread executorThread_;
  std::unordered_map<std::string, rclcpp::GenericSubscription::SharedPtr> subscriptions_;

  // Stats timer
  QTimer statsTimer_;
};

#endif // RQML_RECORDER_BAG_RECORDER_ENGINE_HPP
