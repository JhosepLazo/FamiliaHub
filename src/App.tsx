import { BrowserRouter } from 'react-router-dom'
import AppRouter from './app/AppRouter'
import ErrorBoundary from './components/ErrorBoundary'
import { DialogoProvider } from './components/ui/Dialogo'
import { AuthProvider } from './features/auth/AuthContext'

function App() {
	return (
		<ErrorBoundary>
			<BrowserRouter>
				<AuthProvider>
					<DialogoProvider>
						<AppRouter />
					</DialogoProvider>
				</AuthProvider>
			</BrowserRouter>
		</ErrorBoundary>
	)
}

export default App
