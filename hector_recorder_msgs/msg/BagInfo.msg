# Summary information about a recorded bag file
string name                         # Bag directory name (e.g. "rosbag2_2026_03_07-10_30_00")
string path                         # Absolute path to the bag directory
uint64 size_bytes                   # Total size of all files in the bag directory
string start_time                   # ISO 8601 timestamp of the first message
float64 duration_secs               # Duration of the recording in seconds
uint32 topic_count                  # Number of topics in the bag
uint32 message_count                # Total number of messages across all topics
string recorded_by                  # Who recorded this bag (e.g. "alice@robot-pc")
string storage_id                   # Storage plugin used (e.g. "sqlite3", "mcap")
