import { Navigate, Outlet, useLocation } from 'react-router-dom'
import LoadingScreen from '../components/LoadingScreen'
import { useAuth } from '../features/auth/AuthContext'

export default function RequireAuth() {
	const { user, loading } = useAuth()
	const location = useLocation()

	if (loading) return <LoadingScreen />
	if (!user) {
		const next = encodeURIComponent(location.pathname + location.search)
		return <Navigate to={`/login?next=${next}`} replace />
	}

	return <Outlet />
}
