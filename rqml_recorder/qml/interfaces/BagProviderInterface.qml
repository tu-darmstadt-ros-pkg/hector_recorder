import QtQuick

/**
 * Abstract base interface for bag data providers.
 * Both RecorderInterface (ROS 2 service-based) and LocalBagScanner
 * (filesystem-based) extend this to ensure a consistent API for BagBrowser.
 */
QtObject {
    id: root

    //! Whether this provider supports remote transfer (rsync)
    property bool supportsTransfer: false

    //! Whether this provider supports bag deletion
    property bool supportsDelete: true

    //! Whether this provider supports local playback
    property bool supportsPlayback: false

    // ========================================================================
    // Required API — subclasses must override these
    // ========================================================================

    /**
     * List available bags.
     * @param path  Optional path filter (empty = default location)
     * @param callback  function(bags[]) where each bag has:
     *   { name, path, sizeBytes, startTime, durationSecs, topicCount, messageCount, recordedBy, storageId }
     */
    function listBags(path, callback) {
        console.warn("BagProviderInterface.listBags() not implemented");
    }

    /**
     * Get detailed topic information for a specific bag.
     * @param bagPath  Absolute path to the bag
     * @param callback  function(info, topics[]) where each topic has:
     *   { name, type, messageCount, serializationFormat }
     */
    function getBagDetails(bagPath, callback) {
        console.warn("BagProviderInterface.getBagDetails() not implemented");
    }

    /**
     * Delete a bag.
     * @param bagPath  Absolute path to the bag
     * @param callback  function(success, message)
     */
    function deleteBag(bagPath, callback) {
        console.warn("BagProviderInterface.deleteBag() not implemented");
    }

    /**
     * Fetch provider info (hostname, recordedBy, etc.).
     * @param callback  function({ hostname, recordedBy, configPath })
     */
    function fetchRecorderInfo(callback) {
        console.warn("BagProviderInterface.fetchRecorderInfo() not implemented");
    }
}
