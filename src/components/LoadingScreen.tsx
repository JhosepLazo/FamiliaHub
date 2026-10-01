import { LoaderCircle } from 'lucide-react'

export default function LoadingScreen() {
	return (
		<div className="grid min-h-screen place-items-center bg-[#f4f6f2]">
			<div className="flex items-center gap-3 text-sm font-medium text-slate-500">
				<LoaderCircle className="animate-spin text-[#0f766e]" size={20} />
				Cargando FamiliaHub...
			</div>
		</div>
	)
}
