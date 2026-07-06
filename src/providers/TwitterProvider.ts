// ============================================================================
// Twitter/XProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, VideoFormat, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?twitter\.com\/\w+\/status\/\d+/i,
  /(?:https?:\/\/)?(?:www\.)?x\.com\/\w+\/status\/\d+/i,
  /(?:https?:\/\/)?(?:www\.)?x\.com\/\w+\/photo\/\d+/i,
];

export class TwitterProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "twitter",
    displayName: "Twitter / X",
    icon: "alternate_email",
    color: "#1DA1F2",
    capabilities: [
      ProviderCapability.Video,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [VideoFormat.MP4],
    supportedAudioFormats: [AudioFormat.MP3, AudioFormat.AAC],
    urlPatterns: ["twitter.com", "x.com"],
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
}
