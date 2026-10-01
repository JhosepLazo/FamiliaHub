import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'

type FamiliaContextValue = {
	familia: Tables<'familias'> | null
	membresia: Tables<'miembros_familia'> | null
	loading: boolean
	refresh: () => Promise<void>
}

const FamiliaContext = createContext<FamiliaContextValue | null>(null)

export function FamiliaProvider({ children }: { children: ReactNode }) {
	const { user } = useAuth()
	const [familia, setFamilia] = useState<Tables<'familias'> | null>(null)
	const [membresia, setMembresia] = useState<Tables<'miembros_familia'> | null>(null)
	const [loading, setLoading] = useState(true)

	const refresh = useCallback(async () => {
		if (!user) {
			setFamilia(null)
			setMembresia(null)
			setLoading(false)
			return
		}

		setLoading(true)
		const { data: member } = await supabase
			.from('miembros_familia')
			.select('*')
			.eq('usuario_id', user.id)
			.eq('estado', 'ACTIVO')
			.maybeSingle()

		if (!member) {
			setFamilia(null)
			setMembresia(null)
			setLoading(false)
			return
		}

		const { data: family } = await supabase.from('familias').select('*').eq('id', member.familia_id).single()
		setMembresia(member)
		setFamilia(family ?? null)
		setLoading(false)
	}, [user])

	useEffect(() => { void refresh() }, [refresh])

	const value = useMemo(() => ({ familia, membresia, loading, refresh }), [familia, membresia, loading, refresh])
	return <FamiliaContext.Provider value={value}>{children}</FamiliaContext.Provider>
}

export function useFamilia() {
	const context = useContext(FamiliaContext)
	if (!context) throw new Error('useFamilia debe usarse dentro de FamiliaProvider.')
	return context
}
