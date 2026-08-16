// Adapters translate every vendor failure into one of these. The relay decides
// what to do with them — an adapter never writes to the chat history itself.
export class AdapterError extends Error {
  /**
   * @param {'auth'|'rate_limit'|'timeout'|'refusal'|'unavailable'|'empty'|'config'} code
   */
  constructor(code, message, { cause, retryAfter = null } = {}) {
    super(message, { cause })
    this.name = 'AdapterError'
    this.code = code
    this.retryAfter = retryAfter
  }

  /** Shown by the app in place of a spinner that never ends. */
  get userFacing() {
    switch (this.code) {
      case 'auth':
        return 'AI 凭据无效'
      case 'rate_limit':
        return 'AI 限流中，稍后再试'
      case 'timeout':
        return 'AI 响应超时'
      case 'refusal':
        return 'AI 拒绝了这条请求'
      case 'config':
        return 'AI 未配置'
      case 'empty':
        return 'AI 返回了空回复'
      default:
        return 'AI 暂时不可用'
    }
  }
}

/** Maps an SDK error onto an AdapterError by HTTP status. */
export function fromHttpStatus(status, message, cause) {
  if (status === 401 || status === 403) return new AdapterError('auth', message, { cause })
  if (status === 429) return new AdapterError('rate_limit', message, { cause })
  if (status === 408) return new AdapterError('timeout', message, { cause })
  if (status >= 500) return new AdapterError('unavailable', message, { cause })
  return new AdapterError('unavailable', message, { cause })
}
