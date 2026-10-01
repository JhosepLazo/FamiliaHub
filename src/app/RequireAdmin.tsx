import { Navigate, Outlet } from 'react-router-dom'
import { useFamilia } from '../features/familia/FamiliaContext'

export default function RequireAdmin() {
	const { membresia } = useFamilia()
	return membresia?.rol === 'ADMINISTRADOR' ? <Outlet /> : <Navigate to="/inicio" replace />
}
