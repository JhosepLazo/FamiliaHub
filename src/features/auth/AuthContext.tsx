import type { Session, User } from '@supabase/supabase-js'
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase } from '../../lib/supabase'

type AuthContextValue = {
	session: Session | null
	user: User | null
	loading: boolean
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
	const [session, setSession] = useState<Session | null>(null)
	const [user, setUser] = useState<User | null>(null)
	const [loading, setLoading] = useState(true)

	useEffect(() => {
		let active = true

		// Al renovar el token (cada hora o al volver a la pestaña) llega un usuario nuevo con el mismo id.
		// Se conserva el anterior para que las páginas no se recarguen ni pierdan lo que se estaba escribiendo.
		const aplicar = (nextSession: Session | null, cambioDatos = false) => {
			setSession(nextSession)
			setUser((current) => cambioDatos || current?.id !== nextSession?.user.id ? nextSession?.user ?? null : current)
			setLoading(false)
		}

		supabase.auth.getSession().then(({ data }) => {
			if (active) aplicar(data.session)
		})

		const { data } = supabase.auth.onAuthStateChange((event, nextSession) => aplicar(nextSession, event === 'USER_UPDATED'))

		return () => {
			active = false
			data.subscription.unsubscribe()
		}
	}, [])

	const value = useMemo(() => ({ session, user, loading }), [session, user, loading])
	return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
	const context = useContext(AuthContext)
	if (!context) throw new Error('useAuth debe usarse dentro de AuthProvider.')
	return context
}
