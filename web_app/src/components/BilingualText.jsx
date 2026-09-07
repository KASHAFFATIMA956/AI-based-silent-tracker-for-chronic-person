import { useLanguage } from '../state/LanguageContext'

// Renders exactly ONE of two pre-written strings depending on the language
// toggle — never both stacked together. Mirrors
// mobile_app/lib/widgets/bilingual_text.dart, which itself exists because
// the mobile app's login screen once showed both languages at once and had
// to be fixed to be exclusive (see context/decisions-log.md, 2026-08-27
// entry) — this component is built exclusive from the start so that bug
// class can't recur on web.
export function BilingualText({ en, ur, as: Tag = 'span', ...rest }) {
  const { isRomanUrdu } = useLanguage()
  return <Tag {...rest}>{isRomanUrdu ? ur : en}</Tag>
}
