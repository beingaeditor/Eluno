export const PROTOCOL_VERSION = 1;
export const CHUNK_BYTES = 256 * 1024;
export const MEDIA_TYPES = Object.freeze(['video/mp4', 'video/webm', 'image/jpeg', 'image/png', 'image/webp']);
export const MODULES = Object.freeze([
  { id: 'media', name: 'Media', version: 1 },
  { id: 'search', name: 'Search', version: 1 },
  { id: 'save-copy', name: 'Save a copy', version: 1 }
]);
export const LIMITS = Object.freeze({ devices: 200, rooms: 50, roomMembers: 8, filesPerRequest: 50, roomFiles: 250, concurrentStreams: 8, imageBytes: 50 * 1024 * 1024 });
export function safeDownloadName(name) { return name.replace(/[\x00-\x1f\x7f<>:"/\\|?*]/g, '_').replace(/[. ]+$/, '').slice(0, 120) || 'Eluno-file'; }
