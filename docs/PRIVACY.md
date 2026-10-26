# Eluno beta privacy information

Eluno 0.2.0 runs on your Windows computer and Android devices over your local network. It does not require an account, send analytics, upload content to a cloud service, or contact a hosted signaling/relay service during ordinary use. Building the application downloads dependencies from their registries; that is separate from the installed runtime.

The computer coordinates the connection. Its memory contains device names, selected media metadata, approval state, short-lived connection credentials and in-flight chunks. The computer can observe the media passing through it, including phone-to-computer or phone-to-other-device streams. This is transport encryption to the coordinator, not end-to-end encryption between arbitrary peers.

Only selected files are shared. Eluno uses system file pickers rather than scanning the library. Browser file handles, Android content URIs and session credentials remain in process memory and are lost when the application closes or the web page reloads. Android stores the chosen device name in app preferences; the web client stores its device name locally. The computer stores a private TLS identity in its app-data directory. It is used to authenticate invitations and is not a media library. It must be protected as private application data.

Photos may be temporarily cached in Android's private cache for decoding; the temporary file is removed after decoding. Viewed images and thumbnails can remain in memory until their views/session are cleared. A crash may leave an app-private temporary photo cache file until cleanup or app-data removal. The coordinator does not intentionally persist media. A copy explicitly saved through the download flow is kept at the destination you choose and remains after disconnection. Windows may retain downloaded files in its downloads directory. Operating-system caches and backups have their own behavior; Android app backup and transfer exclusions are configured.

Nearby discovery broadcasts a random service instance, port and protocol/TLS support, along with local addresses. It does not broadcast media names, pairing codes, tokens or certificate keys. Your local network can observe that an Eluno service exists. The visible QR contains private network endpoints, a certificate fingerprint, a pairing code and an expiration; treat it as a temporary invitation.

The connection creator explicitly approves a named device. Stop sharing, remove a peer, disconnect, or close the creator app to end future access. Tokens are held in memory, codes expire after five minutes, pending requests after one minute, and sessions after eight hours. These controls cannot erase content already received or prevent screen recording.

The **Save connection report** action exports a local JSON file containing version information and counts. It is never automatically uploaded. The beta has no published public support endpoint; contact the project maintainer through the future repository's issue workflow after reviewing the report for suitability.

For a complete reset, close Eluno, remove its app data through operating-system tools, and uninstall if desired. Reinstallation with app data preserved may retain the computer's identity. Saved copies must be removed separately from their chosen destinations. See the release procedure for data locations and identity renewal.
