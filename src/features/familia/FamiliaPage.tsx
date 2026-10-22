import { Copy, Share2, UserPlus } from 'lucide-react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { useDialogo } from '../../components/ui/Dialogo'
import MensajeFlotante from '../../components/ui/MensajeFlotante'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../types/database'
import { useAuth } from '../auth/AuthContext'
import { useFamilia } from './FamiliaContext'

type MemberView = Tables<'miembros_familia'> & { nombre: string }
type Invitation = Pick<Tables<'invitaciones'>, 'id' | 'nombre' | 'email' | 'rol' | 'estado' | 'expira_at'>

export default function FamiliaPage() {
	const { user } = useAuth()
	const { familia, membresia } = useFamilia()
	const { confirmar } = useDialogo()
	const isAdmin = membresia?.rol === 'ADMINISTRADOR'
	const [members, setMembers] = useState<MemberView[]>([])
	const [invitations, setInvitations] = useState<Invitation[]>([])
	const [nombre, setNombre] = useState('')
	const [email, setEmail] = useState('')
	const [rol, setRol] = useState<'ADMINISTRADOR' | 'INTEGRANTE'>('INTEGRANTE')
	const [inviteLink, setInviteLink] = useState<string | null>(null)
	const [loading, setLoading] = useState(false)
	const [message, setMessage] = useState<string | null>(null)

	const refresh = useCallback(async () => {
		if (!familia) return

		const { data: rows } = await supabase.from('miembros_familia').select('*').eq('familia_id', familia.id).order('joined_at')
		const ids = rows?.map((row) => row.usuario_id) ?? []
		let profiles: { id: string; nombre: string | null }[] = []

		if (ids.length) profiles = (await supabase.from('perfiles').select('id,nombre').in('id', ids)).data ?? []

		const profileMap = new Map(profiles.map((profile) => [profile.id, profile.nombre ?? 'Integrante']))
		setMembers((rows ?? []).map((row) => ({ ...row, nombre: profileMap.get(row.usuario_id) ?? 'Integrante' })))

		if (isAdmin) {
			const { data } = await supabase
				.from('invitaciones')
				.select('id,nombre,email,rol,estado,expira_at')
				.eq('familia_id', familia.id)
				.eq('estado', 'PENDIENTE')
				.order('created_at', { ascending: false })

			setInvitations(data ?? [])
		}
	}, [familia, isAdmin])

	useEffect(() => { void refresh() }, [refresh])

	const activeCount = useMemo(() => members.filter((member) => member.estado === 'ACTIVO').length, [members])

	const invite = async (event: FormEvent) => {
		event.preventDefault()
		if (!familia) return

		setLoading(true)
		setMessage(null)
		setInviteLink(null)

		const { data, error } = await supabase.functions.invoke('invitar-integrante', {
			body: { familiaId: familia.id, nombre, email, rol },
		})

		if (error || !data?.token) setMessage('No pudimos generar la invitación. Revisa si ya existe una pendiente para ese correo.')
		else {
			setInviteLink(`${window.location.origin}/invitacion/${data.token}`)
			setNombre('')
			setEmail('')
			setRol('INTEGRANTE')
			await refresh()
		}

		setLoading(false)
	}

	const copyInvite = async () => {
		if (!inviteLink) return
		await navigator.clipboard.writeText(inviteLink)
		setMessage('Enlace copiado. Puedes enviarlo por WhatsApp.')
	}

	const shareInvite = async () => {
		if (!inviteLink) return
		if (navigator.share) await navigator.share({ title: 'Invitación FamiliaHub', text: 'Únete a nuestra familia en FamiliaHub.', url: inviteLink })
		else await copyInvite()
	}

	const updateMember = async (id: string, changes: Partial<Pick<Tables<'miembros_familia'>, 'rol' | 'estado'>>) => {
		const nombre = members.find((member) => member.id === id)?.nombre ?? 'este integrante'
		const pregunta = changes.estado === 'INACTIVO'
			? { titulo: `¿Desactivar a ${nombre}?`, mensaje: 'Dejará de ver la familia y perderá su vínculo de WhatsApp. Su historial de pagos se conserva y puedes reactivarlo cuando quieras.', accion: 'Desactivar', peligro: true }
			: changes.rol === 'ADMINISTRADOR'
				? { titulo: `¿Hacer administrador a ${nombre}?`, mensaje: 'Podrá configurar servicios, confirmar montos, validar pagos e invitar integrantes.', accion: 'Hacer administrador' }
				: changes.rol === 'INTEGRANTE'
					? { titulo: `¿Quitarle la administración a ${nombre}?`, mensaje: 'Seguirá en la familia como integrante.', accion: 'Quitar administración' }
					: null
		if (pregunta && !(await confirmar(pregunta))) return
		setMessage(null)
		const { error } = await supabase.from('miembros_familia').update(changes).eq('id', id)
		if (error) setMessage(error.message)
		await refresh()
	}

	const revoke = async (id: string) => {
		const invitacion = invitations.find((item) => item.id === id)
		const seguro = await confirmar({
			titulo: invitacion?.nombre ? `¿Revocar la invitación de ${invitacion.nombre}?` : '¿Revocar la invitación?',
			mensaje: 'El enlace dejará de funcionar. Puedes enviar una invitación nueva cuando quieras.',
			accion: 'Revocar',
			peligro: true,
		})
		if (!seguro) return
		const { error } = await supabase.from('invitaciones').update({ estado: 'REVOCADA' }).eq('id', id)
		setMessage(error ? error.message : 'Invitación revocada.')
		await refresh()
	}

	return (
		<div className="fh-entrada">
			<p className="text-sm font-bold text-slate-800">{activeCount} integrante{activeCount === 1 ? '' : 's'} activo{activeCount === 1 ? '' : 's'} en {familia?.nombre}</p>
			<p className="mt-0.5 text-xs text-slate-500">Invita con un enlace privado; cada persona crea su propio acceso.</p>

			<div className="mt-5 grid gap-3">
				{members.map((member) => (
					<div key={member.id} className="flex flex-col gap-4 rounded-2xl border border-slate-200 bg-white p-5 sm:flex-row sm:items-center sm:justify-between">
						<div className="flex min-w-0 items-center gap-3">
							<div className={`grid size-11 shrink-0 place-items-center rounded-2xl text-base font-extrabold ${member.estado === 'ACTIVO' ? 'bg-linear-to-br from-teal-500 to-cyan-600 text-white shadow-[0_0_18px_-6px_rgb(34_211_238/0.8)]' : 'bg-slate-100 text-slate-400'}`}>{member.nombre.trim().charAt(0).toUpperCase()}</div>
							<div className="min-w-0">
								<p className="truncate font-bold text-slate-900">{member.nombre}{member.usuario_id === user?.id && <span className="ml-1.5 text-xs font-semibold text-slate-400">(tú)</span>}</p>
								<div className="mt-1 flex flex-wrap gap-1.5">
									<span className={`fh-pill ${member.rol === 'ADMINISTRADOR' ? 'bg-cyan-50 text-cyan-800 ring-cyan-200/70' : 'bg-slate-100 text-slate-500 ring-slate-200'}`}>{member.rol === 'ADMINISTRADOR' ? 'Administrador' : 'Integrante'}</span>
									{member.estado !== 'ACTIVO' && <span className="fh-pill bg-slate-100 text-slate-400 ring-slate-200">Inactivo</span>}
								</div>
							</div>
						</div>

						{isAdmin && (
							<div className="flex gap-2">
								<select className="fh-select" value={member.rol} onChange={(e) => void updateMember(member.id, { rol: e.target.value as 'ADMINISTRADOR' | 'INTEGRANTE' })}>
									<option value="INTEGRANTE">Integrante</option>
									<option value="ADMINISTRADOR">Administrador</option>
								</select>
								<select className="fh-select" value={member.estado} onChange={(e) => void updateMember(member.id, { estado: e.target.value as 'ACTIVO' | 'INACTIVO' })}>
									<option value="ACTIVO">Activo</option>
									<option value="INACTIVO">Inactivo</option>
								</select>
							</div>
						)}
					</div>
				))}
			</div>

			{isAdmin && (
				<div className="mt-9 grid gap-6 lg:grid-cols-2">
					<section className="rounded-3xl border border-slate-200 bg-white p-6">
						<div className="flex items-center gap-3">
							<div className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-brand"><UserPlus size={19} /></div>
							<div><h2 className="font-semibold">Invitar integrante</h2><p className="text-xs text-slate-400">Genera un enlace privado de 7 días.</p></div>
						</div>

						<form className="mt-6 space-y-4" onSubmit={invite}>
							<label className="block"><span className="fh-label">Nombre</span><input className="fh-input" required value={nombre} onChange={(e) => setNombre(e.target.value)} /></label>
							<label className="block"><span className="fh-label">Correo</span><input className="fh-input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
							<label className="block"><span className="fh-label">Rol</span><select className="fh-input" value={rol} onChange={(e) => setRol(e.target.value as 'ADMINISTRADOR' | 'INTEGRANTE')}><option value="INTEGRANTE">Integrante</option><option value="ADMINISTRADOR">Administrador</option></select></label>
							<button className="fh-button-primary w-full" disabled={loading}>{loading ? 'Generando...' : 'Generar invitación'}</button>
						</form>

						{inviteLink && (
							<div className="mt-5 rounded-2xl bg-slate-50 p-4">
								<p className="break-all text-xs text-slate-500">{inviteLink}</p>
								<div className="mt-3 flex gap-2">
									<button type="button" className="fh-button-secondary flex items-center gap-2" onClick={copyInvite}><Copy size={15} />Copiar</button>
									<button type="button" className="fh-button-secondary flex items-center gap-2" onClick={shareInvite}><Share2 size={15} />Compartir</button>
								</div>
							</div>
						)}
					</section>

					<section className="rounded-3xl border border-slate-200 bg-white p-6">
						<h2 className="font-semibold">Invitaciones pendientes</h2>
						<div className="mt-5 space-y-3">
							{invitations.length === 0 && <p className="text-sm text-slate-400">No hay invitaciones pendientes.</p>}
							{invitations.map((invitation) => (
								<div key={invitation.id} className="rounded-xl border border-slate-100 p-4">
									<div className="flex items-start justify-between gap-3">
										<div className="min-w-0"><p className="truncate text-sm font-semibold">{invitation.nombre || invitation.email}</p><p className="truncate text-xs text-slate-400">{invitation.email} · {invitation.rol === 'ADMINISTRADOR' ? 'Administrador' : 'Integrante'}</p></div>
										<button className="text-xs font-semibold text-rose-500" onClick={() => void revoke(invitation.id)}>Revocar</button>
									</div>
								</div>
							))}
						</div>
					</section>
				</div>
			)}

			<MensajeFlotante mensaje={message} alCerrar={() => setMessage(null)} />
		</div>
	)
}
