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
	const [loading, setLoading] = useState(true)

	useEffect(() => {
		let active = true

		supabase.auth.getSession().then(({ data }) => {
			if (!active) return
			setSession(data.session)
			setLoading(false)
		})

		const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
			setSession(nextSession)
			setLoading(false)
		})

		return () => {
			active = false
			data.subscription.unsubscribe()
		}
	}, [])

	const value = useMemo(() => ({ session, user: session?.user ?? null, loading }), [session, loading])
	return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
	const context = useContext(AuthContext)
	if (!context) throw new Error('useAuth debe usarse dentro de AuthProvider.')
	return context
}
