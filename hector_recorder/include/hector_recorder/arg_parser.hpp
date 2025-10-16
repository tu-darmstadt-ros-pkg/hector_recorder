#pragma once

#include "CLI11.hpp"
#include "rosbag2_storage/storage_options.hpp"
#include "rosbag2_transport/record_options.hpp"
#include <string>

#include <hector_recorder/utils.h>

namespace hector_recorder
{

class ArgParser
{

public:
  ArgParser() = default;
  ~ArgParser() = default;

  void parseCommandLineArguments( int argc, char **argv, CustomOptions &custom_options,
                                  rosbag2_storage::StorageOptions &storage_options,
                                  rosbag2_transport::RecordOptions &record_options );

private:
  CLI::App parser;
};

} // namespace hector_recorder