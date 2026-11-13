export const APP_LANGUAGES = [{ code: 'en', label: 'English', name: 'English' }] as const
export type AppLanguageCode = 'en'
export const appLanguageLabel = (_code: AppLanguageCode) => 'English'

const fill = (template: string, args: (string | number)[]) => {
  let next = 0
  return template.replace(/%(?:(\d+)\$)?([@d%])/g, (_, position: string | undefined, type: string) =>
    type === '%' ? '%' : String(args[position ? Number(position) - 1 : next++]),
  )
}

export type Localizer = ReturnType<typeof localizer>
export function localizer(_code: AppLanguageCode) {
  const text = (english: string) => english
  const format = (english: string, ...args: (string | number)[]) => fill(english, args)
  return {
    code: 'en' as const, rtl: false, text, format,
    counted: (singular: string, plural: string, count: number) => count === 1 ? singular : plural,
    duration(minutes: number, short = false) {
      if (minutes < 1) return short ? '1m' : '<1m'
      if (minutes < 60) return `${minutes}m`
      const hours = Math.floor(minutes / 60)
      if (hours >= 24) return `${Math.floor(hours / 24)}d`
      const rest = minutes % 60
      return short || rest === 0 ? `${hours}h` : `${hours}h ${rest}m`
    },
  }
}
