declare module 'axios-retry-after' {
  import { AxiosError, AxiosInstance } from 'axios'

  /**
   * Function to enhance Axios instance with retry-after functionality.
   * @param axios Axios instance to be enhanced.
   * @param options Configuration options for retry behavior.
   */
  export default function (
    axios: AxiosInstance,
    options?: AxiosRetryAfterOptions
  ): (error: AxiosError) => Promise<void>

  /**
   * Configuration options for axios-retry-after.
   */
  export interface AxiosRetryAfterOptions {
    /**
     * Function to determine if an error response is retryable.
     * @param error The Axios error to evaluate.
     */
    isRetryable?: (error: AxiosError) => boolean

    /**
     * Function to wait for a specified amount of time.
     * @param error The Axios error that contains retry-after header.
     */
    wait?: (error: AxiosError) => Promise<void>

    /**
     * Function to retry the original request.
     * @param axios The Axios instance used for retrying the request.
     * @param error The Axios error to retry.
     */
    retry?: (axios: AxiosInstance, error: AxiosError) => Promise<any>
  }
}
