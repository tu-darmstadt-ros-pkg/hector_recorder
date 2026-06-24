#include "preset_store.hpp"
#include <QDir>
#include <QStandardPaths>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

static bool isValidPresetName( const QString &name )
{
  if ( name.isEmpty() )
    return false;
  return !name.contains( '/' ) && !name.contains( '\\' ) && !name.contains( ".." );
}

PresetStore::PresetStore( QObject *parent ) : QObject( parent )
{
  std::error_code ec;
  fs::create_directories( presetDir(), ec );
  if ( ec ) {
    qWarning( "PresetStore: failed to create preset directory: %s", ec.message().c_str() );
  }
}

fs::path PresetStore::presetDir() const
{
  return fs::path( QDir::homePath().toStdString() ) / ".ros" / "hector_recorder_presets";
}

fs::path PresetStore::presetPath( const QString &name ) const
{
  return presetDir() / ( name.toStdString() + ".yaml" );
}

QStringList PresetStore::presetNames() const
{
  QStringList names;
  std::error_code ec;
  for ( const auto &entry : fs::directory_iterator( presetDir(), ec ) ) {
    if ( entry.is_regular_file() && entry.path().extension() == ".yaml" ) {
      names.append( QString::fromStdString( entry.path().stem().string() ) );
    }
  }
  names.sort();
  return names;
}

QString PresetStore::load( const QString &name ) const
{
  if ( !isValidPresetName( name ) )
    return {};
  std::ifstream file( presetPath( name ) );
  if ( !file.is_open() )
    return {};
  std::ostringstream ss;
  ss << file.rdbuf();
  return QString::fromStdString( ss.str() );
}

bool PresetStore::save( const QString &name, const QString &yaml )
{
  if ( !isValidPresetName( name ) )
    return false;
  std::error_code ec;
  fs::create_directories( presetDir(), ec );
  std::ofstream file( presetPath( name ) );
  if ( !file.is_open() )
    return false;
  file << yaml.toStdString();
  file.close();
  emit presetsChanged();
  return true;
}

bool PresetStore::remove( const QString &name )
{
  if ( !isValidPresetName( name ) )
    return false;
  std::error_code ec;
  bool ok = fs::remove( presetPath( name ), ec );
  if ( ok )
    emit presetsChanged();
  return ok;
}
