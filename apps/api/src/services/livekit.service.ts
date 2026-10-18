import { AccessToken, RoomServiceClient, TrackSource } from 'livekit-server-sdk';
import { env } from '../config/env.js';

export class LiveKitService {
  private static roomService = new RoomServiceClient(
    env.LIVEKIT_URL,
    env.LIVEKIT_API_KEY,
    env.LIVEKIT_API_SECRET
  );

  /**
   * Generate signed LiveKit JWT AccessToken for a participant
   */
  static async createParticipantToken(params: {
    roomName: string;
    participantId: string;
    participantName: string;
    role: 'ADMIN' | 'TEACHER' | 'STUDENT';
    metadata?: Record<string, any>;
  }): Promise<string> {
    const { roomName, participantId, participantName, role, metadata } = params;
    const isHost = role === 'TEACHER' || role === 'ADMIN';

    const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
      identity: participantId,
      name: participantName,
      ttl: '6h',
      metadata: JSON.stringify(metadata ?? { role }),
    });

    if (isHost) {
      at.addGrant({
        room: roomName,
        roomJoin: true,
        roomCreate: true,
        roomAdmin: true,
        canPublish: true,
        canPublishData: true,
        canSubscribe: true,
        canPublishSources: [
          TrackSource.CAMERA,
          TrackSource.MICROPHONE,
          TrackSource.SCREEN_SHARE,
          TrackSource.SCREEN_SHARE_AUDIO,
        ],
      });
    } else {
      at.addGrant({
        room: roomName,
        roomJoin: true,
        canPublish: true, // Allow student to publish their camera & mic so teacher can see & hear them
        canPublishData: true,
        canSubscribe: true,
        canPublishSources: [
          TrackSource.CAMERA,
          TrackSource.MICROPHONE,
        ],
      });
    }

    return await at.toJwt();
  }

  /**
   * Mute all participants in a room (excluding host if needed)
   */
  static async muteAll(roomName: string): Promise<void> {
    try {
      const participants = await this.roomService.listParticipants(roomName);
      for (const p of participants) {
        // Mute published tracks
        for (const track of p.tracks) {
          if (track.source === TrackSource.MICROPHONE && !track.muted) {
            await this.roomService.mutePublishedTrack(roomName, p.identity, track.sid, true);
          }
        }
      }
    } catch {
      // Ignore if LiveKit server is running offline/mock mode in dev
    }
  }

  /**
   * List all participants currently in a LiveKit room
   */
  static async listParticipants(roomName: string): Promise<any[]> {
    try {
      return await this.roomService.listParticipants(roomName);
    } catch {
      return [];
    }
  }

  /**
   * Update participant publish permissions (e.g. enforce HAND_RAISE_ONLY or lock/unlock speaking)
   * Note: Students NEVER receive TrackSource.SCREEN_SHARE or SCREEN_SHARE_AUDIO.
   */
  static async updateParticipantPermissions(
    roomName: string,
    participantId: string,
    canPublish: boolean
  ): Promise<void> {
    try {
      await this.roomService.updateParticipant(roomName, participantId, undefined, {
        canPublish,
        canPublishData: true,
        canSubscribe: true,
        canPublishSources: canPublish ? [TrackSource.CAMERA, TrackSource.MICROPHONE] : [],
      });
    } catch {
      // Ignore if LiveKit server is running offline/mock mode in dev
    }
  }

  /**
   * Mute a specific track source (microphone or camera) for a participant
   */
  static async muteParticipantTrack(
    roomName: string,
    participantId: string,
    source: TrackSource
  ): Promise<void> {
    try {
      const participants = await this.listParticipants(roomName);
      const participant = participants.find((p) => p.identity === participantId);
      if (participant) {
        for (const track of participant.tracks) {
          if (track.source === source && !track.muted) {
            await this.roomService.mutePublishedTrack(roomName, participantId, track.sid, true);
          }
        }
      }
    } catch {
      // Ignore in dev
    }
  }

  /**
   * Remove/disconnect a participant from the room
   */
  static async removeParticipant(roomName: string, participantId: string): Promise<void> {
    try {
      await this.roomService.removeParticipant(roomName, participantId);
    } catch {
      // Ignore if LiveKit server is running offline in dev
    }
  }

  /**
   * End and delete the room on LiveKit SFU
   */
  static async deleteRoom(roomName: string): Promise<void> {
    try {
      await this.roomService.deleteRoom(roomName);
    } catch {
      // Ignore in dev
    }
  }
}
