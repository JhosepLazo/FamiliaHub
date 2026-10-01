import { Navigate, Outlet } from 'react-router-dom'
import LoadingScreen from '../components/LoadingScreen'
import { useFamilia } from '../features/familia/FamiliaContext'

export default function RequireSinFamilia() {
	const { familia, loading } = useFamilia()

	if (loading) return <LoadingScreen />
	return familia ? <Navigate to="/inicio" replace /> : <Outlet />
}
