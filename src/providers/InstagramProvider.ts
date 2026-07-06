// ============================================================================
// InstagramProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, VideoFormat, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?instagram\.com\/p\/[\w-]+\/?/i,
  /(?:https?:\/\/)?(?:www\.)?instagram\.com\/reel\/[\w-]+\/?/i,
  /(?:https?:\/\/)?(?:www\.)?instagram\.com\/tv\/[\w-]+\/?/i,
  /(?:https?:\/\/)?(?:www\.)?instagram\.com\/[\w.-]+\/?/i,
];

export class InstagramProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "instagram",
    displayName: "Instagram",
    icon: "camera_alt",
    color: "#E4405F",
    capabilities: [
      ProviderCapability.Video,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [VideoFormat.MP4],
    supportedAudioFormats: [AudioFormat.MP3, AudioFormat.AAC],
    urlPatterns: ["instagram.com"],
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
    return args;
  }
}
