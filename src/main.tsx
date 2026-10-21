import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import './styles.css'

// Al publicar una versión nueva, una pestaña que quedó abierta pide páginas que ya no existen.
// Se recarga una vez (como mucho cada 30 segundos, para no entrar en un ciclo si el fallo es de red).
window.addEventListener('vite:preloadError', (event) => {
	try {
		const ultima = Number(sessionStorage.getItem('fh-recarga-version') ?? 0)
		if (Date.now() - ultima < 30_000) return
		sessionStorage.setItem('fh-recarga-version', String(Date.now()))
	} catch {
		// Sin sessionStorage se recarga igual.
	}
	event.preventDefault()
	window.location.reload()
})

createRoot(document.getElementById('root')!).render(
	<StrictMode>
		<App />
	</StrictMode>,
)
