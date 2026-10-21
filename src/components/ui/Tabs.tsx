import type { ReactNode } from 'react'
import { useSearchParams } from 'react-router-dom'

export type TabItem<T extends string> = {
	id: T
	label: string
	icon?: ReactNode
	count?: number
}

// La pestaña activa vive en ?tab= para que los enlaces (también los del bot de WhatsApp) abran la correcta.
export function useTab<T extends string>(items: TabItem<T>[], fallback: T) {
	const [params, setParams] = useSearchParams()
	const actual = params.get('tab')
	const activa = (items.find((item) => item.id === actual)?.id ?? fallback) as T

	const cambiar = (id: T) => {
		const siguiente = new URLSearchParams(params)
		siguiente.set('tab', id)
		setParams(siguiente, { replace: true })
	}

	return [activa, cambiar] as const
}

export default function Tabs<T extends string>({ items, active, onChange }: { items: TabItem<T>[]; active: T; onChange: (id: T) => void }) {
	return (
		<div className="-mx-5 overflow-x-auto px-5 sm:mx-0 sm:px-0 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
			<div role="tablist" className="inline-flex min-w-full gap-1 rounded-2xl border border-white/90 bg-white/70 p-1 shadow-sm backdrop-blur sm:min-w-0">
				{items.map((item) => {
					const selected = item.id === active
					return (
						<button
							key={item.id}
							type="button"
							role="tab"
							aria-selected={selected}
							onClick={() => onChange(item.id)}
							className={`flex flex-1 items-center justify-center gap-2 whitespace-nowrap rounded-xl px-4 py-2.5 text-xs font-bold transition duration-200 active:scale-[0.97] sm:flex-none ${selected
								? 'bg-linear-to-br from-brand to-brand-2 text-white shadow-[0_8px_18px_-10px_rgb(13_148_136/0.9)]'
								: 'text-slate-500 hover:bg-white hover:text-slate-900'}`}
						>
							{item.icon}
							{item.label}
							{item.count ? (
								<span className={`grid min-w-5 place-items-center rounded-full px-1.5 py-0.5 text-[10px] ${selected ? 'bg-white/25 text-white' : 'bg-amber-100 text-amber-800'}`}>{item.count}</span>
							) : null}
						</button>
					)
				})}
			</div>
		</div>
	)
}
