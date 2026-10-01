import { HeartHandshake } from 'lucide-react'

export default function Brand({ compact = false }: { compact?: boolean }) {
	return (
		<div className="flex items-center gap-3">
			<div className="grid size-11 shrink-0 place-items-center rounded-2xl bg-[#123f39] text-white shadow-sm">
				<HeartHandshake size={21} strokeWidth={2} />
			</div>
			{!compact && (
				<div>
					<p className="font-semibold tracking-tight text-slate-900">FamiliaHub</p>
					<p className="text-xs text-slate-500">Tu hogar, más simple.</p>
				</div>
			)}
		</div>
	)
}
