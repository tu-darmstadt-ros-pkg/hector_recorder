#ifndef RQML_RECORDER_LOCAL_BAG_SCANNER_HPP
#define RQML_RECORDER_LOCAL_BAG_SCANNER_HPP

#include <QJSValue>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

/**
 * Filesystem-based bag scanner exposed to QML.
 * Implements the same API contract as RecorderInterface's bag methods
 * (listBags, getBagDetails, deleteBag, fetchRecorderInfo) but reads
 * directly from the local filesystem using rosbag2_storage::MetadataIo.
 */
class LocalBagScanner : public QObject
{
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY( QString scanPath READ scanPath WRITE setScanPath NOTIFY scanPathChanged )
  Q_PROPERTY( bool supportsTransfer READ supportsTransfer CONSTANT )
  Q_PROPERTY( bool supportsDelete READ supportsDelete CONSTANT )

public:
  explicit LocalBagScanner( QObject *parent = nullptr );

  QString scanPath() const;
  void setScanPath( const QString &path );

  bool supportsTransfer() const { return false; }
  bool supportsDelete() const { return true; }

  /**
   * List bags in the scan directory. Calls callback(bags) where bags is an array
   * of { name, path, sizeBytes, startTime, durationSecs, topicCount, messageCount, recordedBy, storageId }.
   */
  Q_INVOKABLE void listBags( const QString &path, QJSValue callback );

  /**
   * Get per-topic details for a bag. Calls callback(info, topics) where topics is an array
   * of { name, type, messageCount, serializationFormat }.
   */
  Q_INVOKABLE void getBagDetails( const QString &bagPath, QJSValue callback );

  /**
   * Delete a bag directory. Calls callback(success, message).
   */
  Q_INVOKABLE void deleteBag( const QString &bagPath, QJSValue callback );

  /**
   * Fetch provider info. Calls callback({ hostname, recordedBy, configPath }).
   */
  Q_INVOKABLE void fetchRecorderInfo( QJSValue callback );

  /**
   * Return directory completions for a partial path.
   * Given "/home/user/ba", returns ["/home/user/bags/", "/home/user/backups/", ...].
   * Supports ~ expansion. Only returns directories.
   */
  Q_INVOKABLE QStringList completePath( const QString &partial ) const;

signals:
  void scanPathChanged();
  void serviceResponse( const QString &serviceName, bool success, const QString &message );

private:
  QString scanPath_;
};

#endif // RQML_RECORDER_LOCAL_BAG_SCANNER_HPP
