.pragma library

function formatBytes(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
}

function formatDuration(duration) {
    let secs = typeof duration === "object" ? (duration.sec || 0) : Math.round(duration);
    let mins = Math.floor(secs / 60);
    let hrs = Math.floor(mins / 60);
    return hrs + ":" + String(mins % 60).padStart(2, '0') + ":"
           + String(secs % 60).padStart(2, '0');
}

function formatBandwidth(bps) {
    if (bps < 1000) return bps.toFixed(0) + " B/s";
    if (bps < 1000000) return (bps / 1000).toFixed(1) + " kB/s";
    return (bps / 1000000).toFixed(1) + " MB/s";
}

function formatFreq(hz) {
    if (hz < 1000) return hz.toFixed(1) + " Hz";
    return (hz / 1000).toFixed(1) + " kHz";
}
