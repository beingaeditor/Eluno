export interface Device { id: string; name: string; online: boolean }
export interface SharedFile { id: string; ownerId: string; name: string; type: string; size: number; allowDownload: boolean }
export interface ReadRequest { id: string; fileId: string; start: number; end: number }
export interface Session { id: string; ownerId: string; code: string | null; pairExpiresAt: number; expiresAt: number; members: Device[]; pending: Device[]; files: SharedFile[] }
export interface Snapshot { version: number; self: { id: string; name: string }; pending: boolean; room: Session | null; reads: ReadRequest[] }
export interface PairingInvitation { v: 1; endpoints: string[]; fingerprint: string; code: string; expiresAt: number }
