import { BrowserRouter } from 'react-router-dom'
import AppRouter from './app/AppRouter'
import ErrorBoundary from './components/ErrorBoundary'
import { AuthProvider } from './features/auth/AuthContext'

function App() {
	return (
		<ErrorBoundary>
			<BrowserRouter>
				<AuthProvider>
					<AppRouter />
				</AuthProvider>
			</BrowserRouter>
		</ErrorBoundary>
	)
}

export default App
