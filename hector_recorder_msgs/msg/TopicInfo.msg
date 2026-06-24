string topic
int64 msg_count
float64 frequency   # Hz
int64 size          # bytes
int64 bandwidth     # bytes/s
string type                         # Message type (e.g. "sensor_msgs/msg/Image")
uint8 publisher_count               # Number of active publishers
string qos_reliability              # QoS reliability string
bool throttled                      # Whether throttle config is applied