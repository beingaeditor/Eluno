# Using Eluno

This guide describes the 0.2.0 internal beta. Supported launch targets are Windows x64 and Android 12+ phones/tablets; physical acceptance remains pending.

## Connect

Install the Windows beta and open **Eluno** from Start. Name your computer and select **Connect another device**. Install the Android beta, open it, enter a recognizable name, and tap **Scan computer invitation**. Allow the camera when scanning. Scan the invitation shown on your own computer, confirm Connect on Android, then approve that named device on Windows.

Use the same private Wi-Fi. A QR invitation lasts five minutes; **Get a new code** creates another. You do not need to enter an IP address, port, or command. Nearby discovery is a convenience; scanning still works if the network blocks discovery. Only invitations shown on a computer you intend to trust should be scanned.

## Share either way

Use **Add media** on Windows or **Add photos or videos** on Android. Eluno asks the system file picker for exactly the items you choose. Select up to 50 at once. They appear on all approved screens in the connection. Your originals stay on the source device and are read as the viewer needs them.

Select **Play** for video or **View** for photos. Video controls include playback, seeking and volume; Windows also provides the browser's fullscreen control and the desktop View → Toggle Fullscreen menu. Android uses the system volume buttons and a full-screen viewer dialog. Photos support previous/next and zoom; viewed photos gain a small preview in the library. Search by name; the web interface also searches device names and filters photos/videos.

Keep both apps open. Android pauses hosting and playback in the background; return to Eluno and retry if a request timed out. Changing Wi-Fi may require restarting Windows Eluno and pairing again. Reloading the web page ends its current session rather than restoring secret credentials.

## Save a copy

Saving is optional. Check **Allow saving copies** before adding media, or enable it per item later. Other devices then see **Save copy**. Android asks where to put the copy; Windows uses its download flow. Keep both devices open until complete and check the saved file. Interrupted saves may leave an incomplete destination file.

Disabling copies removes future download access, while viewing can continue. Anyone who can view media can also retain received content through other means. This permission is a convenient download control, not copy protection.

## End access

**Stop sharing** removes an item from all connected screens. On Windows, **Remove [device name]** removes a peer and the media it supplied. **Disconnect** on the creator computer ends the entire connection. Disconnecting a peer removes only that peer. Sessions also expire after eight hours. Already received bytes and saved copies cannot be recalled.

## Troubleshooting

- **No connection:** use the same home Wi-Fi. Guest networks and VPNs may isolate devices. If Windows asks about Eluno, allow access on private networks. Keep the firewall enabled. Reopen Eluno after network changes and scan a fresh invitation.
- **No nearby computer:** scan the visible QR directly. Discovery is optional and does not establish trust by itself.
- **Camera denied:** enable camera access for Eluno in Android app settings, then scan again.
- **Video cannot play:** try an MP4 containing H.264 video and AAC audio. A filename or container does not guarantee supported codecs. Eluno does not convert media.
- **Photo cannot open:** use JPEG, PNG or WebP, at most 50 MiB. Try a smaller photo if the device is low on memory. HEIC is not supported in this beta.
- **Selected file unavailable:** choose a file stored on the device. Some cloud storage providers expose streams that cannot be sought; those files must first be made available locally.
- **Paused or interrupted:** return the source app to the foreground. Retry the item. If the connection ended, pair again.
- **Need help:** the Windows **Help** dialog can save a connection report while connected. Review it and share it voluntarily with the project maintainer. It contains app/protocol versions and numeric counts, without names, addresses, content or tokens.

The beta has no public support address yet. Keep reports in the project's eventual GitHub issue tracker once the repository exists. Do not include invitations or private media in public reports.
