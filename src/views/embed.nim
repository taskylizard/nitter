# SPDX-License-Identifier: AGPL-3.0-only
import options,algorithm,sequtils,json
import karax/[karaxdsl, vdom]
from jester import Request

import ".."/[types,formatters]
import general, tweet

const doctype = "<!DOCTYPE html>\n"

proc renderVideoEmbed*(tweet: Tweet; cfg: Config; req: Request): string =
  let video = get(tweet.video)
  let thumb = video.thumb
  let vars = video.variants.filterIt(it.contentType == mp4)
  let vidUrl = vars.sortedByIt(it.bitrate)[^1].url
  let prefs = Prefs(hlsPlayback: true, mp4Playback: true)
  let node = buildHtml(html(lang="en")):
    renderHead(prefs, cfg, req, video=vidUrl, images=(@[thumb]))

    body:
      tdiv(class="embed-video"):
        renderVideo(video, prefs, "")

  result = doctype & $node

proc generateOembed*(cfg: Config; typ, title, user, url: string): JsonNode =
  %*{
    "type": typ,
    "version": "1.0",
    "provider_name": "Nitter",
    "provider_url": getUrlPrefix(cfg),
    "title": title,
    "author_name": user,
    "author_url": url
  }
