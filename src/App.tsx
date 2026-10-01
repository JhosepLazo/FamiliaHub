import { FormEvent, useState } from 'react'
import { supabase } from './lib/supabase'

function App() {
	const [email, setEmail] = useState('')
	const [password, setPassword] = useState('')
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const handleLogin = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault()
		setLoading(true)
		setMessage(null)

		const { error } = await supabase.auth.signInWithPassword({ email, password })

		setMessage(error ? 'No pudimos iniciar sesión. Revisa tus datos.' : 'Sesión iniciada correctamente.')
		setLoading(false)
	}

	return (
		<main className="min-h-screen bg-[#f5f7f4] text-slate-900">
			<div className="mx-auto grid min-h-screen max-w-7xl lg:grid-cols-[1.15fr_0.85fr]">
				<section className="hidden flex-col justify-between bg-[#123f39] p-12 text-white lg:flex">
					<div className="flex items-center gap-3">
						<div className="grid size-11 place-items-center rounded-2xl bg-white/10 text-lg font-bold">FH</div>
						<div>
							<p className="text-lg font-semibold">FamiliaHub</p>
							<p className="text-sm text-white/65">Tu hogar, más simple.</p>
						</div>
					</div>

					<div className="max-w-xl">
						<p className="mb-4 text-sm font-medium uppercase tracking-[0.2em] text-emerald-200">Asistente familiar</p>
						<h1 className="text-5xl font-semibold leading-tight">
							Recibos, cuotas y pagos claros para todos en casa.
						</h1>
						<p className="mt-6 max-w-lg text-lg leading-8 text-white/70">
							FamiliaHub organiza lo que hay que pagar, calcula cuánto le toca a cada integrante y mantiene el historial sin depender de mensajes sueltos.
						</p>
					</div>

					<p className="text-sm text-white/50">Privado · Familiar · Automatizado</p>
				</section>

				<section className="flex items-center justify-center px-5 py-10 sm:px-8 lg:px-14">
					<div className="w-full max-w-md">
						<div className="mb-10 lg:hidden">
							<div className="mb-5 grid size-12 place-items-center rounded-2xl bg-[#123f39] font-bold text-white">FH</div>
							<p className="text-2xl font-semibold">FamiliaHub</p>
							<p className="mt-1 text-sm text-slate-500">Tu hogar, más simple.</p>
						</div>

						<p className="text-sm font-medium text-[#0f766e]">Bienvenido</p>
						<h2 className="mt-2 text-3xl font-semibold tracking-tight">Ingresa a tu familia</h2>
						<p className="mt-3 text-sm leading-6 text-slate-500">
							Consulta tus cuotas, próximos vencimientos y pagos desde un solo lugar.
						</p>

						<form className="mt-8 space-y-5" onSubmit={handleLogin}>
							<label className="block">
								<span className="mb-2 block text-sm font-medium">Correo</span>
								<input
									type="email"
									autoComplete="email"
									required
									value={email}
									onChange={(event) => setEmail(event.target.value)}
									className="h-12 w-full rounded-xl border border-slate-200 bg-white px-4 outline-none transition focus:border-[#0f766e] focus:ring-4 focus:ring-emerald-100"
									placeholder="nombre@correo.com"
								/>
							</label>

							<label className="block">
								<span className="mb-2 block text-sm font-medium">Contraseña</span>
								<input
									type="password"
									autoComplete="current-password"
									required
									value={password}
									onChange={(event) => setPassword(event.target.value)}
									className="h-12 w-full rounded-xl border border-slate-200 bg-white px-4 outline-none transition focus:border-[#0f766e] focus:ring-4 focus:ring-emerald-100"
									placeholder="••••••••"
								/>
							</label>

							<button
								type="submit"
								disabled={loading}
								className="h-12 w-full rounded-xl bg-[#0f766e] font-semibold text-white transition hover:bg-[#0b5f59] disabled:cursor-not-allowed disabled:opacity-60"
							>
								{loading ? 'Ingresando...' : 'Ingresar'}
							</button>
						</form>

						{message && <p className="mt-4 rounded-xl bg-white p-3 text-sm text-slate-600">{message}</p>}

						<p className="mt-8 text-center text-xs leading-5 text-slate-400">
							FamiliaHub es un espacio privado. El acceso se habilita mediante invitación familiar.
						</p>
					</div>
				</section>
			</div>
		</main>
	)
}

export default App
