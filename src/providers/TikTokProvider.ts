// ============================================================================
// TikTokProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, VideoFormat, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?tiktok\.com\/@[\w.-]+\/video\/\d+/i,
  /(?:https?:\/\/)?(?:www\.)?tiktok\.com\/@[\w.-]+/i,
  /(?:https?:\/\/)?vm\.tiktok\.com\/[\w-]+/i,
  /(?:https?:\/\/)?vt\.tiktok\.com\/[\w-]+/i,
  /(?:https?:\/\/)?(?:www\.)?tiktok\.com\/t\/[\w-]+/i,
];

export class TikTokProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "tiktok",
    displayName: "TikTok",
    icon: "music_video",
    color: "#000000",
    capabilities: [
      ProviderCapability.Video,
      ProviderCapability.Audio,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [VideoFormat.MP4, VideoFormat.WEBM],
    supportedAudioFormats: [AudioFormat.MP3, AudioFormat.AAC, AudioFormat.OPUS],
    urlPatterns: ["tiktok.com", "vm.tiktok.com", "vt.tiktok.com"],
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
    // TikTok no necesita flags especiales
    return args;
  }
}
