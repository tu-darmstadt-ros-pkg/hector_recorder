#ifndef RQML_RECORDER_BAG_TRANSFER_HPP
#define RQML_RECORDER_BAG_TRANSFER_HPP

#include <QObject>
#include <QProcess>
#include <QString>
#include <QtQml/qqmlregistration.h>

/**
 * Rsync-based bag file transfer helper exposed to QML.
 * Pulls a bag directory from a remote host to the local machine.
 */
class BagTransfer : public QObject
{
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY( bool running READ running NOTIFY runningChanged )
  Q_PROPERTY( double progress READ progress NOTIFY progressChanged )
  Q_PROPERTY( QString statusText READ statusText NOTIFY statusTextChanged )

public:
  explicit BagTransfer( QObject *parent = nullptr );
  ~BagTransfer();

  bool running() const;
  double progress() const;
  QString statusText() const;

  /**
   * Start an rsync transfer.
   * @param hostname Remote host (e.g. "robot-pc")
   * @param remotePath Absolute path to the bag directory on the remote host
   * @param localDir Local directory to store the transferred bag
   */
  Q_INVOKABLE void start( const QString &hostname, const QString &remotePath,
                           const QString &localDir );

  /// Cancel a running transfer.
  Q_INVOKABLE void cancel();

signals:
  void runningChanged();
  void progressChanged();
  void statusTextChanged();
  void finished( bool success, const QString &message, const QString &localPath );

private slots:
  void onReadyReadStdout();
  void onProcessFinished( int exitCode, QProcess::ExitStatus exitStatus );

private:
  QProcess *process_ = nullptr;
  bool running_ = false;
  double progress_ = 0.0;
  QString statusText_;
  QString localPath_;
};

#endif // RQML_RECORDER_BAG_TRANSFER_HPP
