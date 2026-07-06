// ============================================================================
// SoundCloudProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?soundcloud\.com\/[\w.-]+\/[\w.-]+/i,
  /(?:https?:\/\/)?(?:www\.)?soundcloud\.com\/[\w.-]+\/sets\/[\w.-]+/i,
  /(?:https?:\/\/)?(?:www\.)?soundcloud\.com\/[\w.-]+/i,
];

export class SoundCloudProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "soundcloud",
    displayName: "SoundCloud",
    icon: "audiotrack",
    color: "#FF7700",
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
    urlPatterns: ["soundcloud.com"],
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
    // SoundCloud es solo audio, forzamos extracción
    const audioOptions = { ...options, extractAudio: true };
    return super.buildDownloadArgs(audioOptions);
  }
}
