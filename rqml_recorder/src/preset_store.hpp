#ifndef RQML_RECORDER_PRESET_STORE_HPP
#define RQML_RECORDER_PRESET_STORE_HPP

#include <QObject>
#include <QStringList>
#include <QtQml/qqmlregistration.h>
#include <filesystem>

/**
 * Simple file-backed preset store for recorder YAML configs.
 * Stores each preset as an individual .yaml file in ~/.ros/hector_recorder_presets/.
 * Exposed to QML as a singleton.
 */
class PresetStore : public QObject
{
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

  Q_PROPERTY( QStringList presetNames READ presetNames NOTIFY presetsChanged )

public:
  explicit PresetStore( QObject *parent = nullptr );

  QStringList presetNames() const;

  Q_INVOKABLE QString load( const QString &name ) const;
  Q_INVOKABLE bool save( const QString &name, const QString &yaml );
  Q_INVOKABLE bool remove( const QString &name );

signals:
  void presetsChanged();

private:
  std::filesystem::path presetDir() const;
  std::filesystem::path presetPath( const QString &name ) const;
};

#endif // RQML_RECORDER_PRESET_STORE_HPP
