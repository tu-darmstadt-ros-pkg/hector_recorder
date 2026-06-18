#include <QJSEngine>
#include <QMap>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>
#include <QtQml>
#include <QtQuickTest/quicktest.h>

#include <qml6_ros2_plugin/qos.hpp>
#include <qml6_ros2_plugin/ros2.hpp>

// Forward declaration
class MockRos2;
static MockRos2 *s_mockRos2 = nullptr;

// =============================================================================
// MockServiceClient
// =============================================================================
class MockServiceClient : public QObject
{
  Q_OBJECT
  Q_PROPERTY( bool ready READ ready CONSTANT )
  Q_PROPERTY( QString name READ name CONSTANT )
  Q_PROPERTY( int pendingRequests READ pendingRequests CONSTANT )
  Q_PROPERTY( int connectionTimeout READ connectionTimeout WRITE setConnectionTimeout NOTIFY
                  connectionTimeoutChanged )
public:
  MockServiceClient( const QString &name, QJSEngine *engine, QJSValue responseCallback,
                     QObject *parent )
      : QObject( parent ), name_( name ), engine_( engine ),
        responseCallback_( std::move( responseCallback ) )
  {
  }

  bool ready() const { return true; }
  QString name() const { return name_; }
  int pendingRequests() const { return 0; }
  int connectionTimeout() const { return timeout_; }
  void setConnectionTimeout( int t )
  {
    timeout_ = t;
    emit connectionTimeoutChanged();
  }

  Q_INVOKABLE void sendRequestAsync( const QVariantMap &req, const QJSValue &callback )
  {
    auto *timer = new QTimer( this );
    timer->setSingleShot( true );
    timer->setInterval( 0 );
    QJSValue cb = callback;
    QJSValue respCb = responseCallback_;
    QJSEngine *eng = engine_;
    connect( timer, &QTimer::timeout, this, [timer, cb, respCb, req, eng]() mutable {
      timer->deleteLater();
      QJSValue response;
      if ( respCb.isCallable() ) {
        QJSValueList args;
        args << eng->toScriptValue( req );
        response = respCb.call( args );
      } else {
        response = QJSValue::NullValue;
      }
      if ( cb.isCallable() ) {
        QJSValueList args;
        args << response;
        cb.call( args );
      }
    } );
    timer->start();
  }

signals:
  void connectionTimeoutChanged();

private:
  QString name_;
  QJSEngine *engine_;
  QJSValue responseCallback_;
  int timeout_ = 5000;
};

// =============================================================================
// MockPublisher — records published messages via Ros2.publishedMessages
// =============================================================================
class MockPublisher : public QObject
{
  Q_OBJECT
  Q_PROPERTY( QString topic READ topic CONSTANT )
  Q_PROPERTY( QString type READ type CONSTANT )
  Q_PROPERTY( bool isAdvertised READ isAdvertised CONSTANT )
public:
  MockPublisher( const QString &topic, const QString &type, QJSEngine *engine, QObject *parent )
      : QObject( parent ), topic_( topic ), type_( type ), engine_( engine )
  {
  }

  QString topic() const { return topic_; }
  QString type() const { return type_; }
  bool isAdvertised() const { return true; }

  Q_INVOKABLE bool publish( const QVariantMap &msg );

private:
  QString topic_;
  QString type_;
  QJSEngine *engine_;
};

// =============================================================================
// MockRos2 — the C++ singleton registered as "Ros2" in QML
// =============================================================================
class MockRos2 : public QObject
{
  Q_OBJECT

  Q_PROPERTY( QJSValue _mockTopics READ mockTopics WRITE setMockTopics )
  Q_PROPERTY( QJSValue _mockServices READ mockServices WRITE setMockServices )
  Q_PROPERTY( QJSValue _mockTypeMap READ mockTypeMap WRITE setMockTypeMap )
  Q_PROPERTY(
      QJSValue _mockServiceResponses READ mockServiceResponses WRITE setMockServiceResponses )
  Q_PROPERTY( QJSValue publishedMessages READ publishedMessages WRITE setPublishedMessages )

public:
  explicit MockRos2( QObject *parent = nullptr ) : QObject( parent ) {}

  void setEngine( QQmlEngine *engine )
  {
    engine_ = engine;
    reset();
  }

  QQmlEngine *engine() const { return engine_; }

  // --- Property accessors ---
  QJSValue mockTopics() const { return mockTopics_; }
  void setMockTopics( const QJSValue &v ) { mockTopics_ = v; }
  QJSValue mockServices() const { return mockServices_; }
  void setMockServices( const QJSValue &v ) { mockServices_ = v; }
  QJSValue mockTypeMap() const { return mockTypeMap_; }
  void setMockTypeMap( const QJSValue &v ) { mockTypeMap_ = v; }
  QJSValue mockServiceResponses() const { return mockServiceResponses_; }
  void setMockServiceResponses( const QJSValue &v ) { mockServiceResponses_ = v; }
  QJSValue publishedMessages() const { return publishedMessages_; }
  void setPublishedMessages( const QJSValue &v ) { publishedMessages_ = v; }

  Q_INVOKABLE qml6_ros2_plugin::QoSWrapper QoS() { return qml6_ros2_plugin::QoSWrapper(); }

  // --- Query functions ---

  Q_INVOKABLE QStringList queryTopics( const QString &datatype = QString() ) const
  {
    return jsStringList( mockTopics_, datatype );
  }

  Q_INVOKABLE QStringList queryTopicTypes( const QString &name ) const
  {
    return jsStringList( mockTypeMap_, name );
  }

  Q_INVOKABLE QStringList getTopicTypes( const QString &name ) const
  {
    return queryTopicTypes( name );
  }

  Q_INVOKABLE QStringList queryServices( const QString &datatype = QString() ) const
  {
    return jsStringList( mockServices_, datatype );
  }

  Q_INVOKABLE QStringList getServiceTypes( const QString &name ) const
  {
    return jsStringList( mockTypeMap_, name );
  }

  Q_INVOKABLE bool isValidTopic( const QString &topic ) const
  {
    return !topic.isEmpty() && topic.startsWith( "/" ) && topic.size() > 1;
  }

  // --- Factory functions ---

  Q_INVOKABLE QObject *createPublisher( const QString &topic, const QString &type,
                                        quint32 /*queue_size*/ = 10 )
  {
    return new MockPublisher( topic, type, engine_, this );
  }

  Q_INVOKABLE QObject *createServiceClient( const QString &name, const QString & /*type*/ )
  {
    QJSValue respCb;
    if ( engine_ && mockServiceResponses_.isObject() ) {
      QJSValue val = mockServiceResponses_.property( name );
      if ( val.isCallable() ) {
        respCb = val;
      } else if ( val.isObject() && !val.isUndefined() && !val.isNull() ) {
        QJSValue wrapper =
            engine_->evaluate( "(function(resp) { return function() { return resp; }; })" );
        QJSValueList args;
        args << val;
        respCb = wrapper.call( args );
      }
    }
    return new MockServiceClient( name, engine_, respCb, this );
  }

  // --- Mock state management ---

  Q_INVOKABLE void reset()
  {
    if ( !engine_ )
      return;
    mockTopics_ = engine_->newObject();
    mockServices_ = engine_->newObject();
    mockTypeMap_ = engine_->newObject();
    mockServiceResponses_ = engine_->newObject();
    publishedMessages_ = engine_->newArray();
  }

  // --- Subscription registry ---

  Q_INVOKABLE void _registerSubscription( QObject *sub ) { subscriptions_.append( sub ); }
  Q_INVOKABLE void _unregisterSubscription( QObject *sub ) { subscriptions_.removeAll( sub ); }

  Q_INVOKABLE QObject *findSubscription( const QString &topic ) const
  {
    for ( QObject *sub : subscriptions_ ) {
      if ( sub->property( "topic" ).toString() == topic )
        return sub;
    }
    return nullptr;
  }

  // --- Utility ---

  Q_INVOKABLE QJSValue wrapCppMessage( const QJSValue &obj )
  {
    if ( !engine_ )
      return obj;
    if ( !wrapFn_.isCallable() ) {
      wrapFn_ = engine_->evaluate( R"((function wrap(obj) {
        if (obj === null || obj === undefined) return obj;
        if (Array.isArray(obj)) {
          var w = [];
          for (var i = 0; i < obj.length; i++) w.push(wrap(obj[i]));
          w.at = function(idx) { return this[idx]; };
          return w;
        }
        if (typeof obj === "object") {
          var r = {};
          var keys = Object.keys(obj);
          for (var k = 0; k < keys.length; k++) r[keys[k]] = wrap(obj[keys[k]]);
          return r;
        }
        return obj;
      }))" );
    }
    QJSValueList args;
    args << obj;
    return wrapFn_.call( args );
  }

  void recordPublishedMessage( const QJSValue &entry )
  {
    if ( publishedMessages_.isArray() ) {
      int len = publishedMessages_.property( "length" ).toInt();
      publishedMessages_.setProperty( len, entry );
    }
  }

private:
  QStringList jsStringList( const QJSValue &map, const QString &key ) const
  {
    QStringList result;
    if ( !map.isObject() )
      return result;

    QJSValue arr = map.property( key );
    if ( !arr.isArray() && !key.isEmpty() )
      arr = map.property( "" );
    if ( !arr.isArray() )
      return result;

    int len = arr.property( "length" ).toInt();
    result.reserve( len );
    for ( int i = 0; i < len; ++i )
      result.append( arr.property( i ).toString() );
    return result;
  }

  QQmlEngine *engine_ = nullptr;
  QJSValue wrapFn_;

  QJSValue mockTopics_;
  QJSValue mockServices_;
  QJSValue mockTypeMap_;
  QJSValue mockServiceResponses_;
  QJSValue publishedMessages_;

  QList<QObject *> subscriptions_;
};

// --- Deferred implementations that need MockRos2 to be complete ---

bool MockPublisher::publish( const QVariantMap &msg )
{
  if ( !engine_ )
    return false;
  QJSValue entry = engine_->newObject();
  entry.setProperty( "topic", topic_ );
  entry.setProperty( "type", type_ );
  entry.setProperty( "message", engine_->toScriptValue( msg ) );
  s_mockRos2->recordPublishedMessage( entry );
  return true;
}

// =============================================================================
// Setup
// =============================================================================
class Setup : public QObject
{
  Q_OBJECT
public:
  Setup() { s_mockRos2 = &mockRos2_; }

public slots:
  void qmlEngineAvailable( QQmlEngine *engine )
  {
    mockRos2_.setEngine( engine );
    qmlRegisterSingletonInstance( "Ros2", 1, 0, "Ros2", &mockRos2_ );
  }

private:
  MockRos2 mockRos2_;
};

QUICK_TEST_MAIN_WITH_SETUP( RqmlRecorderTest, Setup )
#include "test_plugins.moc"
