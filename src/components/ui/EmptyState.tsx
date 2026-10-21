import type { ReactNode } from 'react'

export default function EmptyState({ icon, title, description, action, className = '' }: {
	icon: ReactNode
	title: string
	description?: string
	action?: ReactNode
	className?: string
}) {
	return (
		<section className={`fh-card flex flex-col items-center px-6 py-10 text-center ${className}`}>
			<div className="grid size-12 place-items-center rounded-2xl bg-linear-to-br from-teal-50 to-cyan-100 text-brand ring-1 ring-cyan-100">{icon}</div>
			<h2 className="mt-4 text-base font-bold text-slate-800">{title}</h2>
			{description && <p className="mt-1.5 max-w-md text-sm leading-6 text-slate-500">{description}</p>}
			{action && <div className="mt-5">{action}</div>}
		</section>
	)
}
