#include "bag_transfer.hpp"
#include <QDir>
#include <QFileInfo>
#include <QHostInfo>
#include <QRegularExpression>
#include <cmath>

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
qint64 BagTransfer::bytesTransferred() const { return bytesTransferred_; }
qint64 BagTransfer::bytesTotal() const { return bytesTotal_; }
double BagTransfer::speed() const { return speed_; }
int BagTransfer::etaSeconds() const { return etaSeconds_; }
QString BagTransfer::sourcePath() const { return sourcePath_; }
QString BagTransfer::destPath() const { return destPath_; }

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

  // Build rsync source path
  QString source;
  if ( isLocal ) {
    source = remotePath + "/";
    sourcePath_ = remotePath;
  } else {
    source = hostname + ":" + remotePath + "/";
    sourcePath_ = hostname + ":" + remotePath;
  }
  QString dest = localPath_ + "/";
  destPath_ = localPath_;

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
  args << "--info=progress2" << "--no-inc-recursive" << source << dest;

  running_ = true;
  progress_ = 0.0;
  bytesTransferred_ = 0;
  bytesTotal_ = 0;
  speed_ = 0.0;
  etaSeconds_ = -1;
  filesTransferred_ = 0;
  filesTotal_ = 0;
  readBuffer_.clear();
  statusText_ = "Starting transfer...";
  emit runningChanged();
  emit progressChanged();
  emit statusTextChanged();
  emit sourcePathChanged();
  emit destPathChanged();

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

static QString formatSize( qint64 bytes )
{
  if ( bytes < 1024 )
    return QString::number( bytes ) + " B";
  if ( bytes < 1024 * 1024 )
    return QString::number( bytes / 1024.0, 'f', 1 ) + " KB";
  if ( bytes < 1024LL * 1024 * 1024 )
    return QString::number( bytes / ( 1024.0 * 1024 ), 'f', 1 ) + " MB";
  return QString::number( bytes / ( 1024.0 * 1024 * 1024 ), 'f', 2 ) + " GB";
}

static QString formatEta( int seconds )
{
  if ( seconds < 0 )
    return "";
  if ( seconds < 60 )
    return QString::number( seconds ) + "s";
  if ( seconds < 3600 )
    return QString::number( seconds / 60 ) + "m " + QString::number( seconds % 60 ) + "s";
  return QString::number( seconds / 3600 ) + "h " + QString::number( ( seconds % 3600 ) / 60 ) +
         "m";
}

static double parseSpeed( const QString &speedStr )
{
  // Parse rsync speed strings like "12.34MB/s", "1.23GB/s", "456.78kB/s", "100B/s"
  static QRegularExpression speedRe( R"(([\d.]+)\s*([kMGT]?)B/s)" );
  auto m = speedRe.match( speedStr );
  if ( !m.hasMatch() )
    return 0.0;

  double val = m.captured( 1 ).toDouble();
  QString unit = m.captured( 2 );
  if ( unit == "k" )
    return val * 1000.0;
  if ( unit == "M" )
    return val * 1000000.0;
  if ( unit == "G" )
    return val * 1000000000.0;
  if ( unit == "T" )
    return val * 1000000000000.0;
  return val;
}

void BagTransfer::onReadyReadStdout()
{
  // rsync --info=progress2 uses \r to overwrite the same line.
  // QProcess::canReadLine() only triggers on \n, so we must read all
  // available data and split on both \r and \n.
  readBuffer_.append( process_->readAllStandardOutput() );

  // Split on \r or \n, keeping the last incomplete chunk in the buffer
  int lastSep = -1;
  for ( int i = readBuffer_.size() - 1; i >= 0; --i ) {
    char c = readBuffer_.at( i );
    if ( c == '\r' || c == '\n' ) {
      lastSep = i;
      break;
    }
  }

  if ( lastSep < 0 )
    return; // No complete line yet

  QByteArray complete = readBuffer_.left( lastSep + 1 );
  readBuffer_ = readBuffer_.mid( lastSep + 1 );

  // Split the complete portion into individual lines
  QString text = QString::fromUtf8( complete );
  static QRegularExpression splitRe( R"([\r\n]+)" );
  QStringList lines = text.split( splitRe, Qt::SkipEmptyParts );

  for ( const QString &line : lines ) {
    parseLine( line.trimmed() );
  }
}

void BagTransfer::parseLine( const QString &line )
{
  if ( line.isEmpty() )
    return;

  // rsync --info=progress2 --no-inc-recursive output looks like:
  //   "  1,234,567  42%   12.34MB/s    0:01:23"
  // or with xfr info:
  //   "  1,234,567  42%   12.34MB/s    0:01:23 (xfr#3, to-chk=7/10)"

  // Parse overall percentage and speed
  static QRegularExpression progressRe( R"(^\s*([\d,]+)\s+(\d+)%\s+([\d.]+\S*/s)\s+(\d+:\d+:\d+))" );
  auto progressMatch = progressRe.match( line );
  if ( progressMatch.hasMatch() ) {
    // Parse transferred bytes (remove commas)
    QString bytesStr = progressMatch.captured( 1 );
    bytesStr.remove( ',' );
    bytesTransferred_ = bytesStr.toLongLong();

    int pct = progressMatch.captured( 2 ).toInt();
    progress_ = static_cast<double>( pct );

    // Parse speed
    QString speedStr = progressMatch.captured( 3 );
    speed_ = parseSpeed( speedStr );

    // Estimate total from percentage — lock in once we have a reliable estimate
    // (pct >= 5 avoids wild swings from early rounding, e.g. 1% = ×100 error)
    if ( pct > 0 ) {
      qint64 estimated = bytesTransferred_ * 100 / pct;
      if ( bytesTotal_ <= 0 && pct >= 5 ) {
        // First reliable estimate — lock it in
        bytesTotal_ = estimated;
      } else if ( bytesTotal_ > 0 ) {
        // Subsequent updates: only adjust if the estimate is within 5% of current
        // (handles edge case where rsync discovers new files mid-transfer)
        double drift = std::abs( static_cast<double>( estimated - bytesTotal_ ) ) /
                        static_cast<double>( bytesTotal_ );
        if ( drift > 0.05 ) {
          bytesTotal_ = estimated;
        }
      }
    }

    // Calculate ETA from remaining bytes and speed
    if ( speed_ > 0.0 && bytesTotal_ > bytesTransferred_ ) {
      double remaining = static_cast<double>( bytesTotal_ - bytesTransferred_ );
      etaSeconds_ = static_cast<int>( remaining / speed_ );
    } else if ( pct >= 100 ) {
      etaSeconds_ = 0;
    }

    // Build human-readable status
    statusText_ = formatSize( bytesTransferred_ );
    if ( bytesTotal_ > 0 ) {
      statusText_ += " of " + formatSize( bytesTotal_ );
    }
    statusText_ += "  (" + QString::number( pct ) + "%)";
    if ( speed_ > 0.0 ) {
      statusText_ += "  " + speedStr;
    }
    if ( etaSeconds_ > 0 ) {
      statusText_ += "  ~" + formatEta( etaSeconds_ ) + " remaining";
    }

    emit progressChanged();
    emit statusTextChanged();
  }

  // Parse file counts from to-chk
  static QRegularExpression chkRe( R"(to-chk=(\d+)/(\d+))" );
  auto chkMatch = chkRe.match( line );
  if ( chkMatch.hasMatch() ) {
    int remaining = chkMatch.captured( 1 ).toInt();
    int total = chkMatch.captured( 2 ).toInt();
    filesTotal_ = total;
    filesTransferred_ = total - remaining;
  }
}

void BagTransfer::onProcessFinished( int exitCode, QProcess::ExitStatus exitStatus )
{
  // Process any remaining data in the buffer
  if ( !readBuffer_.isEmpty() ) {
    QString remaining = QString::fromUtf8( readBuffer_ ).trimmed();
    if ( !remaining.isEmpty() )
      parseLine( remaining );
    readBuffer_.clear();
  }

  running_ = false;
  emit runningChanged();

  if ( exitStatus == QProcess::CrashExit || exitCode != 0 ) {
    QString error = process_->readAllStandardOutput();
    statusText_ = "Transfer failed (exit code " + QString::number( exitCode ) + ")";
    emit statusTextChanged();
    progress_ = 0.0;
    bytesTransferred_ = 0;
    bytesTotal_ = 0;
    speed_ = 0.0;
    etaSeconds_ = -1;
    emit progressChanged();
    emit finished( false, statusText_ + ": " + error, "" );
  } else {
    progress_ = 100.0;
    etaSeconds_ = 0;
    if ( bytesTransferred_ > 0 ) {
      statusText_ = "Transfer complete — " + formatSize( bytesTransferred_ );
    } else {
      statusText_ = "Transfer complete";
    }
    bytesTotal_ = bytesTransferred_;
    emit progressChanged();
    emit statusTextChanged();
    emit finished( true, "Transfer complete", localPath_ );
  }

  process_->deleteLater();
  process_ = nullptr;
}
