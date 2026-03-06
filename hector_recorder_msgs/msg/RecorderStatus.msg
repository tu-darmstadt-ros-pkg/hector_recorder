string output_dir
string config_path
string[] files
hector_recorder_msgs/TopicInfo[] topics
builtin_interfaces/Duration duration
int64 size

# Remote control fields
string node_name                    # Fully qualified node name (for service discovery)
uint8 state                         # Current recorder state
uint8 IDLE=0
uint8 RECORDING=1
uint8 PAUSED=2
string[] available_topics           # All discoverable topics on the ROS graph
string config_yaml                  # Current active YAML config as string