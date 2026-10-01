import type { ReactNode } from 'react'
import Brand from './Brand'

export default function AuthLayout({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) {
	return (
		<main className="min-h-screen bg-[#f4f6f2] text-slate-900">
			<div className="mx-auto grid min-h-screen max-w-7xl lg:grid-cols-[1.1fr_0.9fr]">
				<section className="hidden flex-col justify-between bg-[#123f39] p-12 text-white lg:flex">
					<div className="[&_.bg-\[\#123f39\]]:bg-white/10 [&_.text-slate-900]:text-white [&_.text-slate-500]:text-white/60">
						<Brand />
					</div>
					<div className="max-w-xl">
						<p className="mb-4 text-sm font-semibold uppercase tracking-[0.2em] text-emerald-200">Asistente familiar</p>
						<h1 className="text-5xl font-semibold leading-[1.08] tracking-tight">Todo lo importante del hogar, claro y en un solo lugar.</h1>
						<p className="mt-6 max-w-lg text-lg leading-8 text-white/70">
							FamiliaHub organiza integrantes, recibos, cuotas y pagos para que la familia solo intervenga cuando realmente hace falta.
						</p>
					</div>
					<p className="text-sm text-white/50">Privado · Familiar · Automatizado</p>
				</section>

				<section className="flex items-center justify-center px-5 py-10 sm:px-8 lg:px-14">
					<div className="w-full max-w-md">
						<div className="mb-10 lg:hidden"><Brand /></div>
						<p className="text-sm font-semibold text-[#0f766e]">FamiliaHub</p>
						<h2 className="mt-2 text-3xl font-semibold tracking-tight">{title}</h2>
						<p className="mt-3 text-sm leading-6 text-slate-500">{subtitle}</p>
						<div className="mt-8">{children}</div>
					</div>
				</section>
			</div>
		</main>
	)
}
