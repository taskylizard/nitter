# SPDX-License-Identifier: AGPL-3.0-only

import json, asyncdispatch, options, uri
import times
import jester
import router_utils
import ".."/[types, api, apiutils, query, consts]
import httpclient, strutils
import sequtils

export api

proc videoToJson*(t: Video): JsonNode =
  result = newJObject()
  result["durationMs"] = %t.durationMs
  result["url"] = %t.url
  result["thumb"] = %t.thumb
  result["views"] = %t.views
  result["available"] = %t.available
  result["reason"] = %t.reason
  result["title"] = %t.title
  result["description"] = %t.description
  # result["playbackType"] = %t.playbackType
  # result["variants"] = %t.variants
  # playbackType*: VideoType
  # variants*: seq[VideoVariant]

proc tweetToJson*(t: Tweet): JsonNode =
  result = newJObject()
  result["id"] = %t.id
  result["threadId"] = %t.threadId
  result["replyId"] = %t.replyId
  result["user"] = %*{ "username": t.user.username }
  result["text"] = %t.text
  result["time"] = newJString(times.format(t.time, "yyyy-MM-dd'T'HH:mm:ss"))
  result["reply"] = %t.reply
  result["pinned"] = %t.pinned
  result["hasThread"] = %t.hasThread
  result["available"] = %t.available
  result["tombstone"] = %t.tombstone
  result["location"] = %t.location
  result["source"] = %t.source
  # result["stats"] = toJson(t.stats) # Define conversion for TweetStats type
  # result["retweet"] = t.retweet.map(toJson) # Define conversion for Tweet type
  # result["attribution"] = t.attribution.map(toJson) # Define conversion for User type
  # result["mediaTags"] = toJson(t.mediaTags) # Define conversion for seq[User]
  # result["quote"] = t.quote.map(toJson) # Define conversion for Tweet type
  # result["card"] = t.card.map(toJson) # Define conversion for Card type
  # result["poll"] = t.poll.map(toJson) # Define conversion for Poll type
  # result["gif"] = t.gif.map(toJson) # Define conversion for Gif type
  # result["video"] = videoToJson(t.video.get())
  result["photos"] = %t.photos

proc getUserProfileJson*(username: string): Future[JsonNode] {.async.} =
  let user: User = await getGraphUser(username)
  let response: JsonNode = %*{
    "id": user.id,
    "username": user.username
  }
  result = response

proc getUserTweetsJson*(id: string): Future[JsonNode] {.async.} =
  let tweetsGraph = await getGraphUserTweets(id, TimelineKind.tweets)
  let repliesGraph = await getGraphUserTweets(id, TimelineKind.replies)
  let mediaGraph = await getGraphUserTweets(id, TimelineKind.media)

  let tweetsContent = tweetsGraph.tweets.content[0]
  let tweetsJson = tweetsContent.map(tweetToJson)

  let repliesContent = repliesGraph.tweets.content[0]
  let repliesJson = repliesContent.map(tweetToJson)

  let mediaContent = mediaGraph.tweets.content[0]
  let mediaJson = mediaContent.map(tweetToJson)

  let response: JsonNode = %*{
    "tweets": %tweetsJson,
    "replies": %repliesJson,
    "media": %mediaJson
  }

  result = response

proc searchTimeline*(query: Query; after=""): Future[string] {.async.} =
  let q = genQueryParam(query)
  var
    variables = %*{
      "rawQuery": q,
      "count": 20,
      "product": "Latest",
      "withDownvotePerspective": false,
      "withReactionsMetadata": false,
      "withReactionsPerspective": false
    }
  if after.len > 0:
    variables["cursor"] = % after
  let url = graphSearchTimeline ? {"variables": $variables, "features": gqlFeatures}
  result = await fetchRaw(url, Api.search)

proc getUserTweets*(id: string; after=""): Future[string] {.async.} =
  if id.len == 0: return
  let
    cursor = if after.len > 0: "\"cursor\":\"$1\"," % after else: ""
    variables = userTweetsVariables % [id, cursor]
    params = {"variables": variables, "features": gqlFeatures}
  result = await fetchRaw(graphUserTweets ? params, Api.userTweets)

proc getUserReplies*(id: string; after=""): Future[string] {.async.} =
  if id.len == 0: return
  let
    cursor = if after.len > 0: "\"cursor\":\"$1\"," % after else: ""
    variables = userTweetsVariables % [id, cursor]
    params = {"variables": variables, "features": gqlFeatures}
  result = await fetchRaw(graphUserTweets ? params, Api.userTweetsAndReplies)

proc getUserMedia*(id: string; after=""): Future[string] {.async.} =
  if id.len == 0: return
  let
    cursor = if after.len > 0: "\"cursor\":\"$1\"," % after else: ""
    variables = userTweetsVariables % [id, cursor]
    params = {"variables": variables, "features": gqlFeatures}
  result = await fetchRaw(graphUserTweets ? params, Api.userMedia)

proc getTweetById*(id: string; after=""): Future[string] {.async.} =
  let
    cursor = if after.len > 0: "\"cursor\":\"$1\"," % after else: ""
    variables = tweetVariables % [id, cursor]
    params = {"variables": variables, "features": gqlFeatures}
  result = await fetchRaw(graphTweet ? params, Api.tweetDetail)

proc createTwitterApiRouter*(cfg: Config) =
  router api:
    get "/api/echo":
      resp Http200, {"Content-Type": "text/html"}, "hello, world!"

    get "/api/user/@username":
      let username = @"username"
      let response = await getUserProfileJson(username)
      respJson response

    # get "/api/user/@id/tweets":
    #  let id = @"id"
    #  let response = await getUserTweetsJson(id)
    #  respJson response

    get "/api/user/@username/timeline":
      let username = @"username"
      let query = Query(fromUser: @[username])
      let response = await searchTimeline(query)
      resp Http200, { "Content-Type": "application/json" }, response

    get "/api/user/@id/tweets":
      let id = @"id"
      let after = getCursor()
      let response = await getUserTweets(id, after)
      resp Http200, { "Content-Type": "application/json" }, response

    get "/api/user/@id/replies":
      let id = @"id"
      let response = await getUserReplies(id)
      resp Http200, { "Content-Type": "application/json" }, response

    get "/api/user/@id/media":
      let id = @"id"
      let response = await getUserMedia(id)
      resp Http200, { "Content-Type": "application/json" }, response

    get "/api/tweet/@id":
      let id = @"id"
      let response = await getTweetById(id)
      resp Http200, { "Content-Type": "application/json" }, response
