import { Navigate, Route, Routes } from 'react-router-dom'
import AppShell from '../components/AppShell'
import ForgotPasswordPage from '../features/auth/ForgotPasswordPage'
import InvitePage from '../features/auth/InvitePage'
import LoginPage from '../features/auth/LoginPage'
import RegisterPage from '../features/auth/RegisterPage'
import UpdatePasswordPage from '../features/auth/UpdatePasswordPage'
import FamiliaPage from '../features/familia/FamiliaPage'
import FamiliaScope from '../features/familia/FamiliaScope'
import FamiliaSettingsPage from '../features/familia/FamiliaSettingsPage'
import OnboardingPage from '../features/familia/OnboardingPage'
import InicioPage from '../features/inicio/InicioPage'
import ProfilePage from '../features/perfil/ProfilePage'
import ReciboDetallePage from '../features/recibos/ReciboDetallePage'
import RecibosPage from '../features/recibos/RecibosPage'
import ServicioFormPage from '../features/servicios/ServicioFormPage'
import ServiciosPage from '../features/servicios/ServiciosPage'
import RequireAdmin from './RequireAdmin'
import RequireAuth from './RequireAuth'
import RequireFamilia from './RequireFamilia'
import RequireSinFamilia from './RequireSinFamilia'

export default function AppRouter() {
	return (
		<Routes>
			<Route path="/" element={<Navigate to="/inicio" replace />} />
			<Route path="/login" element={<LoginPage />} />
			<Route path="/registro" element={<RegisterPage />} />
			<Route path="/recuperar" element={<ForgotPasswordPage />} />
			<Route path="/actualizar-contrasena" element={<UpdatePasswordPage />} />
			<Route path="/invitacion/:token" element={<InvitePage />} />

			<Route element={<RequireAuth />}>
				<Route element={<FamiliaScope />}>
					<Route element={<RequireSinFamilia />}>
						<Route path="/onboarding" element={<OnboardingPage />} />
					</Route>
					<Route element={<RequireFamilia />}>
						<Route element={<AppShell />}>
							<Route path="/inicio" element={<InicioPage />} />
							<Route path="/familia" element={<FamiliaPage />} />
							<Route path="/recibos" element={<RecibosPage />} />
							<Route path="/recibos/:id" element={<ReciboDetallePage />} />
							<Route path="/perfil" element={<ProfilePage />} />
							<Route element={<RequireAdmin />}>
								<Route path="/configuracion" element={<FamiliaSettingsPage />} />
								<Route path="/servicios" element={<ServiciosPage />} />
								<Route path="/servicios/nuevo" element={<ServicioFormPage />} />
								<Route path="/servicios/:id/editar" element={<ServicioFormPage />} />
							</Route>
						</Route>
					</Route>
				</Route>
			</Route>

			<Route path="*" element={<Navigate to="/inicio" replace />} />
		</Routes>
	)
}
