// ============================================================================
// BandcampProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?[\w-]+\.bandcamp\.com\/track\/[\w-]+/i,
  /(?:https?:\/\/)?[\w-]+\.bandcamp\.com\/album\/[\w-]+/i,
  /(?:https?:\/\/)?[\w-]+\.bandcamp\.com\/\/?$/i,
  /(?:https?:\/\/)?bandcamp\.com\/[\w-]+\/[\w-]+/i,
];

export class BandcampProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "bandcamp",
    displayName: "Bandcamp",
    icon: "music_note",
    color: "#629AA9",
    capabilities: [
      ProviderCapability.Audio,
      ProviderCapability.Playlist,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [],
    supportedAudioFormats: [
      AudioFormat.MP3,
      AudioFormat.FLAC,
      AudioFormat.AAC,
      AudioFormat.OPUS,
      AudioFormat.OGG,
      AudioFormat.WAV,
    ],
    urlPatterns: ["bandcamp.com"],
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
    const audioOptions = { ...options, extractAudio: true };
    return super.buildDownloadArgs(audioOptions);
  }
}
