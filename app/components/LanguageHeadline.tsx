import styles from './landing.module.css'
export const useHeadlineLanguage = () => 'en' as const
export function LanguageHeadline() {
  return <h2 className={styles.headline}>Clear, consistent English.</h2>
}
