import QtQuick
import QtTest
import "../qml/utils.js" as Utils

Item {
    id: windowRoot
    width: 400
    height: 400

    TestCase {
        name: "UtilsTest"
        when: windowShown

        // ---- formatBytes ----

        function test_01_formatBytes_zero() {
            compare(Utils.formatBytes(0), "0 B");
        }

        function test_02_formatBytes_bytes() {
            compare(Utils.formatBytes(500), "500 B");
            compare(Utils.formatBytes(1023), "1023 B");
        }

        function test_03_formatBytes_kilobytes() {
            compare(Utils.formatBytes(1024), "1.0 KB");
            compare(Utils.formatBytes(1536), "1.5 KB");
            compare(Utils.formatBytes(10240), "10.0 KB");
        }

        function test_04_formatBytes_megabytes() {
            compare(Utils.formatBytes(1048576), "1.0 MB");
            compare(Utils.formatBytes(1572864), "1.5 MB");
        }

        function test_05_formatBytes_gigabytes() {
            compare(Utils.formatBytes(1073741824), "1.0 GB");
            compare(Utils.formatBytes(1610612736), "1.5 GB");
        }

        // ---- formatDuration ----

        function test_06_formatDuration_zero() {
            compare(Utils.formatDuration(0), "0:00:00");
        }

        function test_07_formatDuration_seconds_only() {
            compare(Utils.formatDuration(45), "0:00:45");
        }

        function test_08_formatDuration_minutes_and_seconds() {
            compare(Utils.formatDuration(125), "0:02:05");
        }

        function test_09_formatDuration_hours() {
            compare(Utils.formatDuration(3661), "1:01:01");
            compare(Utils.formatDuration(7200), "2:00:00");
        }

        function test_10_formatDuration_object_input() {
            compare(Utils.formatDuration({ sec: 3665 }), "1:01:05");
            compare(Utils.formatDuration({ sec: 0 }), "0:00:00");
        }

        function test_11_formatDuration_object_missing_sec() {
            compare(Utils.formatDuration({}), "0:00:00");
        }

        // ---- formatBandwidth ----

        function test_12_formatBandwidth_bytes_per_sec() {
            compare(Utils.formatBandwidth(500), "500 B/s");
            compare(Utils.formatBandwidth(999), "999 B/s");
        }

        function test_13_formatBandwidth_kilobytes_per_sec() {
            compare(Utils.formatBandwidth(1000), "1.0 kB/s");
            compare(Utils.formatBandwidth(1500), "1.5 kB/s");
            compare(Utils.formatBandwidth(999999), "1000.0 kB/s");
        }

        function test_14_formatBandwidth_megabytes_per_sec() {
            compare(Utils.formatBandwidth(1000000), "1.0 MB/s");
            compare(Utils.formatBandwidth(1500000), "1.5 MB/s");
        }

        // ---- formatFreq ----

        function test_15_formatFreq_hertz() {
            compare(Utils.formatFreq(0), "0.0 Hz");
            compare(Utils.formatFreq(30), "30.0 Hz");
            compare(Utils.formatFreq(999.9), "999.9 Hz");
        }

        function test_16_formatFreq_kilohertz() {
            compare(Utils.formatFreq(1000), "1.0 kHz");
            compare(Utils.formatFreq(1500), "1.5 kHz");
        }
    }
}
