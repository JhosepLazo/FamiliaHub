import { Navigate, Outlet } from 'react-router-dom'
import LoadingScreen from '../components/LoadingScreen'
import { useFamilia } from '../features/familia/FamiliaContext'

export default function RequireFamilia() {
	const { familia, loading } = useFamilia()

	if (loading) return <LoadingScreen />
	return familia ? <Outlet /> : <Navigate to="/onboarding" replace />
}
