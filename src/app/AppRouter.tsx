import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import AppShell from '../components/AppShell'
import LoadingScreen from '../components/LoadingScreen'
import FamiliaScope from '../features/familia/FamiliaScope'
import RequireAdmin from './RequireAdmin'
import RequireAuth from './RequireAuth'
import RequireFamilia from './RequireFamilia'
import RequireSinFamilia from './RequireSinFamilia'

// Cada página se descarga cuando se abre por primera vez: la primera carga en el celular es más rápida.
const AdministrarPage = lazy(() => import('../features/admin/AdministrarPage'))
const ForgotPasswordPage = lazy(() => import('../features/auth/ForgotPasswordPage'))
const InvitePage = lazy(() => import('../features/auth/InvitePage'))
const LoginPage = lazy(() => import('../features/auth/LoginPage'))
const RegisterPage = lazy(() => import('../features/auth/RegisterPage'))
const UpdatePasswordPage = lazy(() => import('../features/auth/UpdatePasswordPage'))
const OnboardingPage = lazy(() => import('../features/familia/OnboardingPage'))
const InicioPage = lazy(() => import('../features/inicio/InicioPage'))
const ProfilePage = lazy(() => import('../features/perfil/ProfilePage'))
const PagarPage = lazy(() => import('../features/pagos/PagarPage'))
const PagosHubPage = lazy(() => import('../features/pagos/PagosHubPage'))
const ReciboDetallePage = lazy(() => import('../features/recibos/ReciboDetallePage'))
const RecibosPage = lazy(() => import('../features/recibos/RecibosPage'))
const ServicioFormPage = lazy(() => import('../features/servicios/ServicioFormPage'))

export default function AppRouter() {
	return (
		<Suspense fallback={<LoadingScreen />}>
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
		</Suspense>
	)
}
