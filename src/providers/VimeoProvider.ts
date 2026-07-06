// ============================================================================
// VimeoProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, VideoFormat, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?vimeo\.com\/\d+/i,
  /(?:https?:\/\/)?(?:www\.)?vimeo\.com\/[\w-]+\/[\w-]+/i,
  /(?:https?:\/\/)?player\.vimeo\.com\/video\/\d+/i,
];

export class VimeoProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "vimeo",
    displayName: "Vimeo",
    icon: "videocam",
    color: "#1AB7EA",
    capabilities: [
      ProviderCapability.Video,
      ProviderCapability.Audio,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [VideoFormat.MP4, VideoFormat.WEBM, VideoFormat.MKV],
    supportedAudioFormats: [AudioFormat.MP3, AudioFormat.AAC, AudioFormat.FLAC, AudioFormat.OGG],
    urlPatterns: ["vimeo.com"],
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
