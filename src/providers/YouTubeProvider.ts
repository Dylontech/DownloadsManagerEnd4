// ============================================================================
// YouTubeProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, VideoFormat, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/watch\?v=[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/embed\/[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/v\/[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/shorts\/[\w-]+/i,
  /(?:https?:\/\/)?youtu\.be\/[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/playlist\?list=[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/@[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?youtube\.com\/channel\/UC[\w-]+/i,
];

export class YouTubeProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "youtube",
    displayName: "YouTube",
    icon: "play_circle",
    color: "#FF0000",
    capabilities: [
      ProviderCapability.Video,
      ProviderCapability.Audio,
      ProviderCapability.Playlist,
      ProviderCapability.Channel,
      ProviderCapability.Subtitles,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [VideoFormat.MP4, VideoFormat.WEBM, VideoFormat.MKV],
    supportedAudioFormats: [AudioFormat.MP3, AudioFormat.AAC, AudioFormat.OPUS, AudioFormat.FLAC, AudioFormat.WAV, AudioFormat.OGG],
    urlPatterns: ["youtube.com", "youtu.be"],
  };

  constructor(private ytDlpAdapter: YtDlpAdapter) {
    super();
  }

  match(url: string): boolean {
    return URL_PATTERNS.some((pattern) => pattern.test(url));
  }

  async getInfo(url: string, _options?: Partial<DownloadOptions>): Promise<MediaInfo> {
    return this.ytDlpAdapter.extractInfo(url);
  }

  buildDownloadArgs(options: DownloadOptions): string[] {
    const args = super.buildDownloadArgs(options);

    // YouTube-specific optimizations
    if (!options.extractAudio) {
      // Preferir MP4 contenedor para mejor compatibilidad
      args.push("--merge-output-format", "mp4");
    }

    // Playlist handling
    if (options.url.includes("playlist")) {
      args.push("--yes-playlist");
    }

    return args;
  }
}
