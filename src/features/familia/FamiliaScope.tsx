import { Outlet } from 'react-router-dom'
import { FamiliaProvider } from './FamiliaContext'

export default function FamiliaScope() {
	return <FamiliaProvider><Outlet /></FamiliaProvider>
}
