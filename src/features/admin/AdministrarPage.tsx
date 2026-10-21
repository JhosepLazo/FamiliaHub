import { HousePlug, MessageCircle, Settings2, Users } from 'lucide-react'
import PageHeader from '../../components/ui/PageHeader'
import Tabs, { useTab, type TabItem } from '../../components/ui/Tabs'
import FamiliaPage from '../familia/FamiliaPage'
import FamiliaSettingsPage from '../familia/FamiliaSettingsPage'
import ServiciosPage from '../servicios/ServiciosPage'
import WhatsAppFamiliaSection from '../whatsapp/WhatsAppFamiliaSection'

type TabAdmin = 'servicios' | 'integrantes' | 'familia' | 'whatsapp'

const items: TabItem<TabAdmin>[] = [
	{ id: 'servicios', label: 'Servicios', icon: <HousePlug size={15} /> },
	{ id: 'integrantes', label: 'Integrantes', icon: <Users size={15} /> },
	{ id: 'familia', label: 'Familia y cobros', icon: <Settings2 size={15} /> },
	{ id: 'whatsapp', label: 'WhatsApp', icon: <MessageCircle size={15} /> },
]

// Módulo Administrar (solo administradores): une lo que antes eran Servicios, Familia y Configuración.
export default function AdministrarPage() {
	const [tab, setTab] = useTab(items, 'servicios')

	return (
		<div>
			<PageHeader eyebrow="Administrar" title="Tu hogar" description="Servicios, integrantes, cobros y el asistente de WhatsApp, en un solo lugar." />
			<div className="mt-6"><Tabs items={items} active={tab} onChange={setTab} /></div>
			<div className="mt-6">
				{tab === 'servicios' && <ServiciosPage />}
				{tab === 'integrantes' && <FamiliaPage />}
				{tab === 'familia' && <FamiliaSettingsPage />}
				{tab === 'whatsapp' && <div className="fh-entrada"><WhatsAppFamiliaSection /></div>}
			</div>
		</div>
	)
}
