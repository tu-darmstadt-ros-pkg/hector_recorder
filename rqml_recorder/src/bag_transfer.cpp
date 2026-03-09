#include "bag_transfer.hpp"
#include <QDir>
#include <QFileInfo>
#include <QHostInfo>
#include <QRegularExpression>

BagTransfer::BagTransfer( QObject *parent ) : QObject( parent ) {}

BagTransfer::~BagTransfer()
{
  if ( process_ ) {
    process_->kill();
    process_->waitForFinished( 3000 );
  }
}

bool BagTransfer::running() const { return running_; }
double BagTransfer::progress() const { return progress_; }
QString BagTransfer::statusText() const { return statusText_; }

void BagTransfer::start( const QString &hostname, const QString &remotePath,
                          const QString &localDir )
{
  if ( running_ )
    return;

  // Expand ~ to home directory and clean up double slashes
  QString expandedDir = localDir;
  if ( expandedDir.startsWith( "~/" ) || expandedDir == "~" ) {
    expandedDir = QDir::homePath() + expandedDir.mid( 1 );
  }
  expandedDir = QDir::cleanPath( expandedDir );

  // Ensure local directory exists
  QDir().mkpath( expandedDir );

  // Extract bag directory name from remote path
  QString bagName = QFileInfo( remotePath ).fileName();
  localPath_ = QDir::cleanPath( expandedDir + "/" + bagName );

  // Detect if the recorder is on the same machine (local transfer)
  QString localHostname = QHostInfo::localHostName();
  bool isLocal = hostname == localHostname || hostname == "localhost" || hostname == "127.0.0.1";

  // Build rsync command
  // -a = archive mode (recursive, preserve permissions, etc.)
  // --progress gives per-file progress output we can parse
  // Trailing slash on source means "contents of directory"
  QString source;
  if ( isLocal ) {
    source = remotePath + "/";
  } else {
    source = hostname + ":" + remotePath + "/";
  }
  QString dest = localPath_ + "/";

  QDir().mkpath( localPath_ );

  process_ = new QProcess( this );
  process_->setProcessChannelMode( QProcess::MergedChannels );

  connect( process_, &QProcess::readyReadStandardOutput, this, &BagTransfer::onReadyReadStdout );
  connect( process_, QOverload<int, QProcess::ExitStatus>::of( &QProcess::finished ), this,
           &BagTransfer::onProcessFinished );

  QStringList args;
  args << "-a";
  if ( !isLocal )
    args << "-z"; // Only compress for remote transfers
  args << "--progress" << source << dest;

  running_ = true;
  progress_ = 0.0;
  statusText_ = "Starting transfer...";
  emit runningChanged();
  emit progressChanged();
  emit statusTextChanged();

  process_->start( "rsync", args );
}

void BagTransfer::cancel()
{
  if ( process_ && running_ ) {
    process_->kill();
    statusText_ = "Cancelled";
    emit statusTextChanged();
  }
}

void BagTransfer::onReadyReadStdout()
{
  while ( process_->canReadLine() ) {
    QString line = QString::fromUtf8( process_->readLine() ).trimmed();
    if ( line.isEmpty() )
      continue;

    // rsync --progress output lines look like:
    // "  1,234,567 100%   12.34MB/s    0:00:01 (xfr#1, to-chk=5/10)"
    // We parse the percentage and the to-chk for overall progress
    static QRegularExpression percentRe( R"((\d+)%)" );
    static QRegularExpression chkRe( R"(to-chk=(\d+)/(\d+))" );

    auto chkMatch = chkRe.match( line );
    if ( chkMatch.hasMatch() ) {
      int remaining = chkMatch.captured( 1 ).toInt();
      int total = chkMatch.captured( 2 ).toInt();
      if ( total > 0 ) {
        progress_ = 100.0 * ( total - remaining ) / total;
        emit progressChanged();
      }
    }

    auto pctMatch = percentRe.match( line );
    if ( pctMatch.hasMatch() ) {
      statusText_ = line;
      emit statusTextChanged();
    }
  }
}

void BagTransfer::onProcessFinished( int exitCode, QProcess::ExitStatus exitStatus )
{
  running_ = false;
  emit runningChanged();

  if ( exitStatus == QProcess::CrashExit || exitCode != 0 ) {
    QString error = process_->readAllStandardOutput();
    statusText_ = "Transfer failed (exit code " + QString::number( exitCode ) + ")";
    emit statusTextChanged();
    progress_ = 0.0;
    emit progressChanged();
    emit finished( false, statusText_ + ": " + error, "" );
  } else {
    progress_ = 100.0;
    statusText_ = "Transfer complete";
    emit progressChanged();
    emit statusTextChanged();
    emit finished( true, "Transfer complete", localPath_ );
  }

  process_->deleteLater();
  process_ = nullptr;
}
