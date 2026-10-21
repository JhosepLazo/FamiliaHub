import { ArrowLeft } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'

export default function PageHeader({ eyebrow, title, description, actions, backTo }: {
	eyebrow?: string
	title: ReactNode
	description?: ReactNode
	actions?: ReactNode
	backTo?: string
}) {
	return (
		<div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
			<div className="flex min-w-0 items-start gap-4">
				{backTo && (
					<Link to={backTo} aria-label="Volver" className="mt-1 grid size-10 shrink-0 place-items-center rounded-xl border border-white/90 bg-white/80 text-slate-500 shadow-sm backdrop-blur transition hover:-translate-x-0.5 hover:text-slate-900 active:scale-95">
						<ArrowLeft size={17} />
					</Link>
				)}
				<div className="min-w-0">
					{eyebrow && <p className="fh-eyebrow">{eyebrow}</p>}
					<h1 className="mt-1.5 text-[1.75rem] font-extrabold leading-tight tracking-tight text-slate-900 sm:text-3xl">{title}</h1>
					{description && <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500">{description}</p>}
				</div>
			</div>
			{actions && <div className="flex shrink-0 flex-wrap gap-2">{actions}</div>}
		</div>
	)
}
