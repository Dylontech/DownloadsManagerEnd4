// ============================================================================
// Providers Index — Factory para crear todos los providers
// ============================================================================

import type { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";
import type { IProvider } from "./IProvider.js";
import { YouTubeProvider } from "./YouTubeProvider.js";
import { TwitchProvider } from "./TwitchProvider.js";
import { TikTokProvider } from "./TikTokProvider.js";
import { InstagramProvider } from "./InstagramProvider.js";
import { TwitterProvider } from "./TwitterProvider.js";
import { VimeoProvider } from "./VimeoProvider.js";
import { SoundCloudProvider } from "./SoundCloudProvider.js";
import { BandcampProvider } from "./BandcampProvider.js";

/**
 * Crea y retorna todos los providers registrados.
 * Inyección de dependencias manual.
 */
export function createAllProviders(ytDlpAdapter: YtDlpAdapter): IProvider[] {
  return [
    new YouTubeProvider(ytDlpAdapter),
    new TwitchProvider(ytDlpAdapter),
    new TikTokProvider(ytDlpAdapter),
    new InstagramProvider(ytDlpAdapter),
    new TwitterProvider(ytDlpAdapter),
    new VimeoProvider(ytDlpAdapter),
    new SoundCloudProvider(ytDlpAdapter),
    new BandcampProvider(ytDlpAdapter),
  ];
}

export {
  YouTubeProvider,
  TwitchProvider,
  TikTokProvider,
  InstagramProvider,
  TwitterProvider,
  VimeoProvider,
  SoundCloudProvider,
  BandcampProvider,
};

export type {
  IProvider,
};
