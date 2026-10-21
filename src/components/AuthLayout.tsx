import { BellRing, MessageCircle, ReceiptText, ShieldCheck } from 'lucide-react'
import type { ReactNode } from 'react'
import Brand from './Brand'

const destacados = [
	{ icon: ReceiptText, texto: 'Recibos y cuotas al día' },
	{ icon: MessageCircle, texto: 'Asistente en WhatsApp' },
	{ icon: BellRing, texto: 'Avisos automáticos' },
	{ icon: ShieldCheck, texto: 'Privado para tu familia' },
]

export default function AuthLayout({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) {
	return (
		<main className="min-h-screen text-slate-900">
			<div className="grid min-h-screen lg:grid-cols-[1.1fr_0.9fr]">
				<section className="relative hidden flex-col justify-between overflow-hidden bg-fh-night p-12 text-white lg:flex">
					<div className="pointer-events-none absolute inset-0 bg-[radial-gradient(640px_420px_at_10%_10%,rgb(20_184_166/0.32),transparent_65%),radial-gradient(560px_460px_at_95%_85%,rgb(34_211_238/0.22),transparent_65%),radial-gradient(480px_360px_at_60%_40%,rgb(139_92_246/0.14),transparent_70%)]" />
					<div className="pointer-events-none absolute inset-0 bg-[linear-gradient(rgb(255_255_255/0.04)_1px,transparent_1px),linear-gradient(90deg,rgb(255_255_255/0.04)_1px,transparent_1px)] bg-[size:44px_44px] [mask-image:radial-gradient(ellipse_at_center,black_35%,transparent_80%)]" />

					<div className="relative"><Brand tone="dark" /></div>

					<div className="relative max-w-xl">
						<p className="mb-5 inline-flex items-center gap-2 rounded-full border border-cyan-300/20 bg-cyan-300/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-cyan-200">
							<span className="size-1.5 rounded-full bg-cyan-300 shadow-[0_0_10px_#67e8f9]" />Asistente familiar
						</p>
						<h1 className="text-5xl font-semibold leading-[1.06] tracking-tight">
							Todo lo importante del hogar, <span className="fh-glow-text">claro y en un solo lugar.</span>
						</h1>
						<p className="mt-6 max-w-lg text-lg leading-8 text-slate-300/80">
							FamiliaHub organiza integrantes, recibos, cuotas y pagos para que la familia solo intervenga cuando realmente hace falta.
						</p>
						<div className="mt-9 grid max-w-lg grid-cols-2 gap-3">
							{destacados.map(({ icon: Icono, texto }) => (
								<div key={texto} className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/[0.04] px-4 py-3 text-sm text-slate-200 backdrop-blur">
									<Icono size={17} className="shrink-0 text-cyan-300" />{texto}
								</div>
							))}
						</div>
					</div>

					<p className="relative text-sm text-slate-400">Privado · Familiar · Automatizado</p>
				</section>

				<section className="flex items-center justify-center px-5 py-10 sm:px-8 lg:px-14">
					<div className="w-full max-w-md rounded-3xl border border-white/80 bg-white/70 p-6 shadow-[0_24px_60px_-30px_rgb(15_23_42/0.35)] backdrop-blur-xl sm:p-8">
						<div className="mb-8 lg:hidden"><Brand /></div>
						<p className="hidden text-sm font-semibold text-teal-700 lg:block">FamiliaHub</p>
						<h2 className="mt-2 text-3xl font-semibold tracking-tight">{title}</h2>
						<p className="mt-3 text-sm leading-6 text-slate-500">{subtitle}</p>
						<div className="mt-8">{children}</div>
					</div>
				</section>
			</div>
		</main>
	)
}
