import { HeartHandshake } from 'lucide-react'

export default function Brand({ compact = false, tone = 'light' }: { compact?: boolean; tone?: 'light' | 'dark' }) {
	return (
		<div className="flex items-center gap-3">
			<div className="relative grid size-11 shrink-0 place-items-center rounded-2xl bg-linear-to-br from-teal-500 via-teal-600 to-cyan-700 text-white shadow-[0_0_26px_-6px_rgb(34_211_238/0.75)] ring-1 ring-white/20">
				<HeartHandshake size={21} strokeWidth={2} />
			</div>
			{!compact && (
				<div>
					<p className={`font-semibold tracking-tight ${tone === 'dark' ? 'text-white' : 'text-slate-900'}`}>FamiliaHub</p>
					<p className={`text-xs ${tone === 'dark' ? 'text-cyan-100/60' : 'text-slate-500'}`}>Tu hogar, más simple.</p>
				</div>
			)}
		</div>
	)
}
