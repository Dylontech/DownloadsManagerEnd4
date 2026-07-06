// ============================================================================
// TwitchProvider
// ============================================================================

import { BaseProvider } from "./BaseProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";
import { ProviderCapability, VideoFormat, AudioFormat } from "../types/index.js";
import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

const URL_PATTERNS = [
  /(?:https?:\/\/)?(?:www\.)?twitch\.tv\/[\w-]+(?:\/video\/\d+)?/i,
  /(?:https?:\/\/)?(?:www\.)?twitch\.tv\/[\w-]+\/clip\/[\w-]+/i,
  /(?:https?:\/\/)?clips\.twitch\.tv\/[\w-]+/i,
];

export class TwitchProvider extends BaseProvider {
  readonly info: ProviderInfo = {
    name: "twitch",
    displayName: "Twitch",
    icon: "live_tv",
    color: "#9146FF",
    capabilities: [
      ProviderCapability.Video,
      ProviderCapability.Audio,
      ProviderCapability.Thumbnail,
      ProviderCapability.Metadata,
    ],
    supportedVideoFormats: [VideoFormat.MP4, VideoFormat.MKV],
    supportedAudioFormats: [AudioFormat.MP3, AudioFormat.AAC, AudioFormat.OPUS],
    urlPatterns: ["twitch.tv", "clips.twitch.tv"],
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

    // Twitch-specific: usar mejor formato disponible
    if (!options.customFormat && options.quality !== "auto") {
      // Twitch suele tener un solo formato de video
      args.push("--merge-output-format", "mkv");
    }

    return args;
  }
}
