import { LoaderCircle } from 'lucide-react'

export default function LoadingScreen() {
	return (
		<div className="grid min-h-screen place-items-center bg-transparent">
			<div className="flex items-center gap-3 text-sm font-medium text-slate-500">
				<LoaderCircle className="animate-spin text-brand" size={20} />
				Cargando FamiliaHub...
			</div>
		</div>
	)
}
