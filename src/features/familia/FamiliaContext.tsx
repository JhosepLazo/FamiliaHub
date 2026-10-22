import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { conectarEnVivo } from '../../lib/enVivo'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'

type Perfil = Pick<Tables<'perfiles'>, 'nombre' | 'usuario'>

type FamiliaContextValue = {
	familia: Tables<'familias'> | null
	membresia: Tables<'miembros_familia'> | null
	perfil: Perfil | null
	loading: boolean
	refresh: () => Promise<void>
}

const FamiliaContext = createContext<FamiliaContextValue | null>(null)

export function FamiliaProvider({ children }: { children: ReactNode }) {
	const { user } = useAuth()
	const [familia, setFamilia] = useState<Tables<'familias'> | null>(null)
	const [membresia, setMembresia] = useState<Tables<'miembros_familia'> | null>(null)
	const [perfil, setPerfil] = useState<Perfil | null>(null)
	const [loading, setLoading] = useState(true)

	const userId = user?.id ?? null
	// Usuario para el que ya se cargó la familia: al refrescar al mismo usuario no se vuelve a la pantalla de
	// carga, así la página abierta no se desmonta.
	const cargadoPara = useRef<string | null>(null)

	const refresh = useCallback(async () => {
		if (!userId) {
			cargadoPara.current = null
			setFamilia(null)
			setMembresia(null)
			setPerfil(null)
			setLoading(false)
			return
		}

		if (cargadoPara.current !== userId) setLoading(true)
		const [{ data: member }, { data: profile }] = await Promise.all([
			supabase.from('miembros_familia').select('*').eq('usuario_id', userId).eq('estado', 'ACTIVO').maybeSingle(),
			supabase.from('perfiles').select('nombre, usuario').eq('id', userId).maybeSingle(),
		])

		const { data: family } = member
			? await supabase.from('familias').select('*').eq('id', member.familia_id).single()
			: { data: null }
		// Si nada cambió se conserva el mismo objeto, para que las páginas que dependen de él no vuelvan a cargar.
		setMembresia((current) => igual(current, member) ? current : member ?? null)
		setFamilia((current) => igual(current, family) ? current : family ?? null)
		setPerfil((current) => igual(current, profile) ? current : profile ?? null)
		cargadoPara.current = userId
		setLoading(false)
	}, [userId])

	useEffect(() => { void refresh() }, [refresh])
	useEffect(() => { conectarEnVivo(familia?.id ?? null) }, [familia?.id])

	const value = useMemo(() => ({ familia, membresia, perfil, loading, refresh }), [familia, membresia, perfil, loading, refresh])
	return <FamiliaContext.Provider value={value}>{children}</FamiliaContext.Provider>
}

function igual(a: unknown, b: unknown) {
	return JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
}

export function useFamilia() {
	const context = useContext(FamiliaContext)
	if (!context) throw new Error('useFamilia debe usarse dentro de FamiliaProvider.')
	return context
}
