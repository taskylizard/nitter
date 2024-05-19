// noinspection TypeScriptUnresolvedReference

import axios from 'axios'
import { AxiosInstance, AxiosRequestConfig } from 'axios'
import fastq from 'fastq'
import { Logger } from 'pino'
import retry from 'axios-retry-after'
import { LRUCache } from 'lru-cache'

const GET_USER_POSITIVE_TTL_MS = process.env.GET_USER_POSITIVE_TTL
  ? parseInt(process.env.GET_USER_POSITIVE_TTL, 10) * 1000
  : 30 * 24 * 3600 * 1000
const GET_USER_NEGATIVE_TTL_MS = process.env.GET_USER_NEGATIVE_TTL
  ? parseInt(process.env.GET_USER_NEGATIVE_TTL, 10) * 1000
  : 3600 * 1000
const GET_TWEETS_POSITIVE_TTL_MS = process.env.GET_TWEETS_POSITIVE_TTL
  ? parseInt(process.env.GET_TWEETS_POSITIVE_TTL, 10) * 1000
  : 60 * 1000
const GET_TWEETS_NEGATIVE_TTL_MS = process.env.GET_TWEETS_NEGATIVE_TTL
  ? parseInt(process.env.GET_TWEETS_NEGATIVE_TTL, 10) * 1000
  : 60 * 1000
const GET_TWEET_POSITIVE_TTL_MS = process.env.GET_TWEET_POSITIVE_TTL
  ? parseInt(process.env.GET_TWEET_POSITIVE_TTL, 10) * 1000
  : 60 * 1000
const GET_TWEET_NEGATIVE_TTL_MS = process.env.GET_TWEET_NEGATIVE_TTL
  ? parseInt(process.env.GET_TWEET_NEGATIVE_TTL, 10) * 1000
  : 60 * 1000

export interface Job {
  reqId: string
  url: string
  params?: Record<string, any>
}

export interface JobResponse {
  status: number
  data: any
}

export class Proxy {
  private readonly cache: LRUCache<string, JobResponse>
  private readonly client: AxiosInstance
  private readonly queue: fastq.queueAsPromised<Job, JobResponse>
  private counter: { requests: number }
  private timeWindowMillis = 15 * 60 * 1000
  private maxRequestsPerAccount = 15 * 60

  constructor(
    private log: Logger,
    private baseUrl: string,
    private concurrency: number,
    retryAfterMillis: number,
    maxCacheSize: number
  ) {
    this.cache = new LRUCache({ max: maxCacheSize })
    this.queue = fastq.promise(this, this.sendRequest, concurrency)
    this.client = axios.create()
    this.counter = {
      requests: 0
    }

    setInterval(() => {
      this.counter.requests = 0
    }, this.timeWindowMillis)

    if (retryAfterMillis) {
      this.client.interceptors.response.use(
        null,
        retry(this.client, {
          // Determine when we should attempt to retry
          isRetryable(error) {
            log.debug(
              {
                status: error.response?.status,
                headers: error.response?.headers
              },
              'checking retryable'
            )
            return (
              error.response && error.response.status === 429
              // Use X-Retry-After rather than Retry-After, and cap retry delay at 60 seconds
              // && error.response.headers['x-retry-after'] && error.response.headers['x-retry-after'] <= 60
            )
          },
          // Customize the wait behavior
          wait(error) {
            log.debug(
              {
                status: error.response?.status,
                headers: error.response?.headers
              },
              'waiting for retry'
            )
            return new Promise(
              // Use X-Retry-After rather than Retry-After
              // resolve => setTimeout(resolve, error.response.headers['x-retry-after'])
              (resolve) => setTimeout(resolve, retryAfterMillis)
            )
          }
        })
      )
    }
  }

  async getUser(username: string, options?: { reqId?: string }) {
    const key = `usernames:${username}`

    if (this.cache.has(key)) {
      return this.cache.get(key)
    }

    const result = await this.queue.push({
      url: `/api/user/${username}`,
      reqId: options?.reqId
    })

    if (result.status === 200) {
      this.cache.set(key, result, { ttl: GET_USER_POSITIVE_TTL_MS })
    }
    if (result.status === 404) {
      this.cache.set(key, result, { ttl: GET_USER_NEGATIVE_TTL_MS })
    }

    return result
  }

  async getUserTweets(
    userId: string,
    cursor?: string,
    options?: { reqId?: string }
  ) {
    const key = `users:${userId}:tweets:${cursor ?? 'last'}`

    if (this.cache.has(key)) {
      return this.cache.get(key)
    }

    const result = await this.queue.push({
      url: `/api/user/${userId}/tweets`,
      params: { cursor },
      reqId: options?.reqId
    })

    if (result.status === 200) {
      this.cache.set(key, result, { ttl: GET_TWEETS_POSITIVE_TTL_MS })
    }
    if (result.status === 404) {
      this.cache.set(key, result, { ttl: GET_TWEETS_NEGATIVE_TTL_MS })
    }

    return result
  }

  async getTweetById(tweetId: string, options?: { reqId?: string }) {
    const key = `tweets:${tweetId}`

    if (this.cache.has(key)) {
      return this.cache.get(key)
    }

    const result = await this.queue.push({
      url: `/api/tweet/${tweetId}`,
      reqId: options?.reqId
    })

    if (result.status === 200) {
      this.cache.set(key, result, { ttl: GET_TWEET_POSITIVE_TTL_MS })
    }
    if (result.status === 404) {
      this.cache.set(key, result, { ttl: GET_TWEET_NEGATIVE_TTL_MS })
    }

    return result
  }

  private async sendRequest(job: Job): Promise<any> {
    const { reqId, url, params } = job

    if (this.counter.requests > this.concurrency * this.maxRequestsPerAccount) {
      return {
        status: 429
      }
    }

    let config = {
      url,
      method: 'get',
      baseURL: this.baseUrl,
      params
    } as AxiosRequestConfig

    this.log.trace({ config, reqId: reqId }, 'sending request to nitter')

    try {
      const response = await this.client.request(config)

      this.log.trace(
        {
          status: response.status,
          data: response.data,
          reqId: reqId
        },
        'nitter response'
      )

      return {
        status: response.status,
        data: response.data
      } as JobResponse
    } catch (err) {
      this.log.warn({ err, reqId }, 'nitter error')

      if (err.name === 'AxiosError') {
        this.counter.requests = Number.MAX_SAFE_INTEGER

        return {
          status: 429
        } as JobResponse
      }

      return {
        status: 500
      }
    }
  }
}
