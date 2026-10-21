import { History, ShieldCheck, WalletCards, Wallet } from 'lucide-react'
import PageHeader from '../../components/ui/PageHeader'
import Tabs, { useTab, type TabItem } from '../../components/ui/Tabs'
import MisCuotasPage from '../cuotas/MisCuotasPage'
import { useCurrentFinance } from '../cuotas/useCurrentFinance'
import { useFamilia } from '../familia/FamiliaContext'
import PagosPage from './PagosPage'

type TabPagos = 'por-pagar' | 'mis-pagos' | 'validar' | 'historial'

// Módulo Pagos: une lo que antes eran "Mis cuotas" y "Pagos y validaciones".
export default function PagosHubPage() {
	const { membresia } = useFamilia()
	const { adminAttention, pagosParaValidar } = useCurrentFinance()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const porValidar = isAdmin ? adminAttention.pagosPorValidar : pagosParaValidar

	const items: TabItem<TabPagos>[] = [
		{ id: 'por-pagar', label: 'Por pagar', icon: <Wallet size={15} /> },
		{ id: 'mis-pagos', label: 'Mis pagos', icon: <WalletCards size={15} /> },
		...(isAdmin || porValidar > 0 ? [{ id: 'validar' as const, label: 'Por validar', icon: <ShieldCheck size={15} />, count: porValidar }] : []),
		...(isAdmin ? [{ id: 'historial' as const, label: 'Historial', icon: <History size={15} /> }] : []),
	]
	const [tab, setTab] = useTab(items, 'por-pagar')

	return (
		<div>
			<PageHeader eyebrow="Pagos" title="Tus pagos" description="Paga tus cuotas, revisa lo que enviaste y confirma lo que te pagaron." />
			<div className="mt-6"><Tabs items={items} active={tab} onChange={setTab} /></div>
			<div className="mt-6">
				{tab === 'por-pagar' && <MisCuotasPage />}
				{tab === 'mis-pagos' && <PagosPage vista="MIOS" />}
				{tab === 'validar' && <PagosPage vista="VALIDAR" />}
				{tab === 'historial' && <PagosPage vista="HISTORIAL" />}
			</div>
		</div>
	)
}
