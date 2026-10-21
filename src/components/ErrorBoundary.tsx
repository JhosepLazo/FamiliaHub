import { RotateCcw } from 'lucide-react'
import { Component, type ReactNode } from 'react'

// Si una página falla (o no se pudo descargar por falta de conexión), se muestra un aviso con un botón para
// recargar en lugar de dejar la pantalla en blanco.
export default class ErrorBoundary extends Component<{ children: ReactNode }, { error: boolean }> {
	state = { error: false }

	static getDerivedStateFromError() {
		return { error: true }
	}

	componentDidCatch(error: unknown) {
		console.error(error)
	}

	render() {
		if (!this.state.error) return this.props.children

		return (
			<div className="grid min-h-screen place-items-center bg-transparent px-5">
				<div className="fh-card max-w-sm p-6 text-center">
					<h1 className="text-lg font-semibold text-slate-900">No pudimos abrir esta página</h1>
					<p className="mt-2 text-sm leading-6 text-slate-500">Puede ser la conexión o que acabamos de publicar una versión nueva. Recarga para seguir donde estabas.</p>
					<button type="button" onClick={() => window.location.reload()} className="fh-button-primary mt-5 w-full"><RotateCcw size={16} />Recargar</button>
				</div>
			</div>
		)
	}
}
