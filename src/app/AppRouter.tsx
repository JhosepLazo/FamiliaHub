import { Navigate, Route, Routes } from 'react-router-dom'
import AppShell from '../components/AppShell'
import AdministrarPage from '../features/admin/AdministrarPage'
import ForgotPasswordPage from '../features/auth/ForgotPasswordPage'
import InvitePage from '../features/auth/InvitePage'
import LoginPage from '../features/auth/LoginPage'
import RegisterPage from '../features/auth/RegisterPage'
import UpdatePasswordPage from '../features/auth/UpdatePasswordPage'
import FamiliaScope from '../features/familia/FamiliaScope'
import OnboardingPage from '../features/familia/OnboardingPage'
import InicioPage from '../features/inicio/InicioPage'
import ProfilePage from '../features/perfil/ProfilePage'
import PagarPage from '../features/pagos/PagarPage'
import PagosHubPage from '../features/pagos/PagosHubPage'
import ReciboDetallePage from '../features/recibos/ReciboDetallePage'
import RecibosPage from '../features/recibos/RecibosPage'
import ServicioFormPage from '../features/servicios/ServicioFormPage'
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
							<Route path="/pagos" element={<PagosHubPage />} />
							<Route path="/pagar" element={<PagarPage />} />
							<Route path="/recibos" element={<RecibosPage />} />
							<Route path="/recibos/:id" element={<ReciboDetallePage />} />
							<Route path="/perfil" element={<ProfilePage />} />
							{/* Direcciones anteriores: siguen funcionando (enlaces guardados y mensajes del bot). */}
							<Route path="/mis-cuotas" element={<Navigate to="/pagos" replace />} />
							<Route element={<RequireAdmin />}>
								<Route path="/administrar" element={<AdministrarPage />} />
								<Route path="/servicios" element={<Navigate to="/administrar?tab=servicios" replace />} />
								<Route path="/familia" element={<Navigate to="/administrar?tab=integrantes" replace />} />
								<Route path="/configuracion" element={<Navigate to="/administrar?tab=familia" replace />} />
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
