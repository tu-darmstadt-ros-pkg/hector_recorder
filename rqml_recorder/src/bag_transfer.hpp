#ifndef RQML_RECORDER_BAG_TRANSFER_HPP
#define RQML_RECORDER_BAG_TRANSFER_HPP

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
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
  Q_PROPERTY( qint64 bytesTransferred READ bytesTransferred NOTIFY progressChanged )
  Q_PROPERTY( qint64 bytesTotal READ bytesTotal NOTIFY progressChanged )
  Q_PROPERTY( double speed READ speed NOTIFY progressChanged )
  Q_PROPERTY( int etaSeconds READ etaSeconds NOTIFY progressChanged )
  Q_PROPERTY( QString sourcePath READ sourcePath NOTIFY sourcePathChanged )
  Q_PROPERTY( QString destPath READ destPath NOTIFY destPathChanged )
  Q_PROPERTY( QString failureCommand READ failureCommand NOTIFY failureChanged )
  Q_PROPERTY( QString failureOutput READ failureOutput NOTIFY failureChanged )

public:
  explicit BagTransfer( QObject *parent = nullptr );
  ~BagTransfer();

  bool running() const;
  double progress() const;
  QString statusText() const;
  qint64 bytesTransferred() const;
  qint64 bytesTotal() const;
  double speed() const;
  int etaSeconds() const;
  QString sourcePath() const;
  QString destPath() const;

  /// Shell-safe rsync command line, available after a failed transfer so the
  /// user can re-run it in a terminal (where SSH can prompt interactively).
  QString failureCommand() const;
  /// Captured tail of the rsync/ssh output from the failed transfer.
  QString failureOutput() const;

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
  void sourcePathChanged();
  void destPathChanged();
  void failureChanged();
  void finished( bool success, const QString &message, const QString &localPath );

private slots:
  void onReadyReadStdout();
  void onProcessFinished( int exitCode, QProcess::ExitStatus exitStatus );

private:
  void parseLine( const QString &line );

  QProcess *process_ = nullptr;
  bool running_ = false;
  double progress_ = 0.0;
  QString statusText_;
  QString localPath_;
  QString sourcePath_;
  QString destPath_;
  QString program_;       ///< rsync program name, kept to rebuild the command
  QStringList arguments_; ///< rsync arguments, kept to rebuild the command
  QString failureCommand_;
  QString failureOutput_;
  QStringList recentOutput_; ///< rolling tail of rsync output lines
  qint64 bytesTransferred_ = 0;
  qint64 bytesTotal_ = 0;
  double speed_ = 0.0;
  int etaSeconds_ = -1;
  int filesTransferred_ = 0;
  int filesTotal_ = 0;
  QByteArray readBuffer_;
};

#endif // RQML_RECORDER_BAG_TRANSFER_HPP
