// Open-Meteo needs no API key and no paid developer account, which keeps the
// weather line on the Home screen free of Apple's WeatherKit requirements.
const ENDPOINT = 'https://api.open-meteo.com/v1/forecast'
const CACHE_MS = 30 * 60 * 1000

// WMO weather interpretation codes, condensed to what a greeting line needs.
const WMO = new Map([
  [0, '晴'], [1, '晴'], [2, '多云'], [3, '阴'],
  [45, '雾'], [48, '雾凇'],
  [51, '小毛雨'], [53, '毛雨'], [55, '大毛雨'],
  [56, '冻毛雨'], [57, '冻毛雨'],
  [61, '小雨'], [63, '中雨'], [65, '大雨'],
  [66, '冻雨'], [67, '冻雨'],
  [71, '小雪'], [73, '中雪'], [75, '大雪'], [77, '雪粒'],
  [80, '阵雨'], [81, '阵雨'], [82, '强阵雨'],
  [85, '阵雪'], [86, '强阵雪'],
  [95, '雷阵雨'], [96, '雷阵雨伴冰雹'], [99, '雷阵雨伴冰雹'],
])

const advise = (code, precipProbability) => {
  if (code >= 95) return '有雷，别出门'
  if ((precipProbability ?? 0) >= 50 || (code >= 51 && code <= 82)) return '带伞'
  if (code >= 71 && code <= 86) return '路滑'
  return null
}

export function createWeather({ lat = process.env.HOME_LAT, lon = process.env.HOME_LON, fetchImpl = fetch } = {}) {
  let cache = null

  return {
    get configured() {
      return Boolean(lat && lon)
    },

    /** Returns null when unconfigured or unreachable — Home just hides the line. */
    async current(now = Date.now()) {
      if (!lat || !lon) return null
      if (cache && now - cache.at < CACHE_MS) return cache.value

      const url = new URL(ENDPOINT)
      url.searchParams.set('latitude', String(lat))
      url.searchParams.set('longitude', String(lon))
      url.searchParams.set('current', 'temperature_2m,weather_code')
      url.searchParams.set('daily', 'temperature_2m_max,temperature_2m_min,precipitation_probability_max')
      url.searchParams.set('timezone', 'auto')
      url.searchParams.set('forecast_days', '1')

      try {
        const res = await fetchImpl(url, { signal: AbortSignal.timeout(6000) })
        if (!res.ok) throw new Error(`open-meteo ${res.status}`)
        const data = await res.json()

        const code = data.current?.weather_code ?? 0
        const precipProbability = data.daily?.precipitation_probability_max?.[0] ?? null
        const value = {
          summary: WMO.get(code) ?? '—',
          code,
          temp: Math.round(data.current?.temperature_2m ?? 0),
          low: Math.round(data.daily?.temperature_2m_min?.[0] ?? 0),
          high: Math.round(data.daily?.temperature_2m_max?.[0] ?? 0),
          precipProbability,
          advice: advise(code, precipProbability),
        }
        cache = { at: now, value }
        return value
      } catch {
        // Stale data beats no greeting line at all.
        return cache?.value ?? null
      }
    },
  }
}
