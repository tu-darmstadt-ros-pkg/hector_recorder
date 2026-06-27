string node_name                    # Fully qualified node name (for service discovery)
uint8 state                         # Current recorder state
uint8 IDLE=0
uint8 RECORDING=1
uint8 PAUSED=2

# Onboard presets (populated when recorder has a preset_dir configured)
string[] preset_names           # Available preset names (file stems in preset_dir)
string active_preset            # Name of the last applied preset, empty if none

# Live recording data (changes every tick while recording)
string output_dir
string[] files
hector_recorder_msgs/TopicInfo[] topics
builtin_interfaces/Duration duration
int64 size