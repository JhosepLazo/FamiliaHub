export function safeNext(value: string | null, fallback = '/inicio') {
	return value && value.startsWith('/') && !value.startsWith('//') ? value : fallback
}
