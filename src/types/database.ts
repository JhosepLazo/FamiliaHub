export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      aportes: {
        Row: {
          anulacion_motivo: string | null
          anulado_at: string | null
          anulado_por: string | null
          creado_por: string | null
          created_at: string
          cuota_id: string
          destino: Database["public"]["Enums"]["destino_aporte"]
          estado: Database["public"]["Enums"]["estado_aporte"]
          familia_id: string
          id: string
          metodo: Database["public"]["Enums"]["metodo_pago_familiar"] | null
          monto: number
          nota: string | null
          pagador_miembro_id: string
          receptor_miembro_id: string | null
          rechazo_motivo: string | null
          recibo_id: string
          referencia: string | null
          tipo: Database["public"]["Enums"]["tipo_aporte"]
          validado_at: string | null
          validado_por: string | null
        }
        Insert: {
          anulacion_motivo?: string | null
          anulado_at?: string | null
          anulado_por?: string | null
          creado_por?: string | null
          created_at?: string
          cuota_id: string
          destino: Database["public"]["Enums"]["destino_aporte"]
          estado?: Database["public"]["Enums"]["estado_aporte"]
          familia_id: string
          id?: string
          metodo?: Database["public"]["Enums"]["metodo_pago_familiar"] | null
          monto: number
          nota?: string | null
          pagador_miembro_id: string
          receptor_miembro_id?: string | null
          rechazo_motivo?: string | null
          recibo_id: string
          referencia?: string | null
          tipo: Database["public"]["Enums"]["tipo_aporte"]
          validado_at?: string | null
          validado_por?: string | null
        }
        Update: {
          anulacion_motivo?: string | null
          anulado_at?: string | null
          anulado_por?: string | null
          creado_por?: string | null
          created_at?: string
          cuota_id?: string
          destino?: Database["public"]["Enums"]["destino_aporte"]
          estado?: Database["public"]["Enums"]["estado_aporte"]
          familia_id?: string
          id?: string
          metodo?: Database["public"]["Enums"]["metodo_pago_familiar"] | null
          monto?: number
          nota?: string | null
          pagador_miembro_id?: string
          receptor_miembro_id?: string | null
          rechazo_motivo?: string | null
          recibo_id?: string
          referencia?: string | null
          tipo?: Database["public"]["Enums"]["tipo_aporte"]
          validado_at?: string | null
          validado_por?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "aportes_cuota_id_fkey"
            columns: ["cuota_id"]
            isOneToOne: false
            referencedRelation: "cuotas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "aportes_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "aportes_pagador_miembro_id_fkey"
            columns: ["pagador_miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "aportes_receptor_miembro_id_fkey"
            columns: ["receptor_miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "aportes_recibo_id_fkey"
            columns: ["recibo_id"]
            isOneToOne: false
            referencedRelation: "recibos"
            referencedColumns: ["id"]
          },
        ]
      }
      categorias: {
        Row: {
          activo: boolean
          created_at: string
          familia_id: string
          icono: string | null
          id: string
          nombre: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          familia_id: string
          icono?: string | null
          id?: string
          nombre: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          familia_id?: string
          icono?: string | null
          id?: string
          nombre?: string
        }
        Relationships: [
          {
            foreignKeyName: "categorias_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      concepto_participantes: {
        Row: {
          concepto_id: string
          created_at: string
          id: string
          miembro_id: string
          modalidad: Database["public"]["Enums"]["modalidad_participante_concepto"]
          orden: number
          valor: number | null
        }
        Insert: {
          concepto_id: string
          created_at?: string
          id?: string
          miembro_id: string
          modalidad: Database["public"]["Enums"]["modalidad_participante_concepto"]
          orden?: number
          valor?: number | null
        }
        Update: {
          concepto_id?: string
          created_at?: string
          id?: string
          miembro_id?: string
          modalidad?: Database["public"]["Enums"]["modalidad_participante_concepto"]
          orden?: number
          valor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "concepto_participantes_concepto_id_fkey"
            columns: ["concepto_id"]
            isOneToOne: false
            referencedRelation: "conceptos_pago"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "concepto_participantes_miembro_id_fkey"
            columns: ["miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
        ]
      }
      conceptos_pago: {
        Row: {
          activo: boolean
          categoria_id: string
          created_at: string
          dia_vencimiento: number | null
          dias_anticipacion_aporte: number
          fallback_manual: boolean
          familia_id: string
          fecha_inicio_generacion: string
          frecuencia: Database["public"]["Enums"]["frecuencia_concepto"]
          id: string
          metodo_obtencion: Database["public"]["Enums"]["metodo_obtencion_monto"]
          monto_fijo: number | null
          nombre: string
          plantilla_id: string | null
          proveedor_id: string
          reparto_resto:
            | Database["public"]["Enums"]["tipo_reparto_resto"]
            | null
          tipo_distribucion: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          tipo_vencimiento: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          categoria_id: string
          created_at?: string
          dia_vencimiento?: number | null
          dias_anticipacion_aporte?: number
          fallback_manual?: boolean
          familia_id: string
          fecha_inicio_generacion?: string
          frecuencia?: Database["public"]["Enums"]["frecuencia_concepto"]
          id?: string
          metodo_obtencion: Database["public"]["Enums"]["metodo_obtencion_monto"]
          monto_fijo?: number | null
          nombre: string
          plantilla_id?: string | null
          proveedor_id: string
          reparto_resto?:
            | Database["public"]["Enums"]["tipo_reparto_resto"]
            | null
          tipo_distribucion?: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          tipo_vencimiento: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          categoria_id?: string
          created_at?: string
          dia_vencimiento?: number | null
          dias_anticipacion_aporte?: number
          fallback_manual?: boolean
          familia_id?: string
          fecha_inicio_generacion?: string
          frecuencia?: Database["public"]["Enums"]["frecuencia_concepto"]
          id?: string
          metodo_obtencion?: Database["public"]["Enums"]["metodo_obtencion_monto"]
          monto_fijo?: number | null
          nombre?: string
          plantilla_id?: string | null
          proveedor_id?: string
          reparto_resto?:
            | Database["public"]["Enums"]["tipo_reparto_resto"]
            | null
          tipo_distribucion?: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          tipo_vencimiento?: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "conceptos_pago_categoria_id_fkey"
            columns: ["categoria_id"]
            isOneToOne: false
            referencedRelation: "categorias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conceptos_pago_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conceptos_pago_plantilla_id_fkey"
            columns: ["plantilla_id"]
            isOneToOne: false
            referencedRelation: "plantillas_servicio"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conceptos_pago_proveedor_id_fkey"
            columns: ["proveedor_id"]
            isOneToOne: false
            referencedRelation: "proveedores"
            referencedColumns: ["id"]
          },
        ]
      }
      configuracion_pago_familiar: {
        Row: {
          activo: boolean
          created_at: string
          familia_id: string
          id: string
          instrucciones: string | null
          metodo: Database["public"]["Enums"]["metodo_pago_familiar"]
          qr_storage_path: string | null
          referencia: string
          titular: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          familia_id: string
          id?: string
          instrucciones?: string | null
          metodo?: Database["public"]["Enums"]["metodo_pago_familiar"]
          qr_storage_path?: string | null
          referencia: string
          titular: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          familia_id?: string
          id?: string
          instrucciones?: string | null
          metodo?: Database["public"]["Enums"]["metodo_pago_familiar"]
          qr_storage_path?: string | null
          referencia?: string
          titular?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "configuracion_pago_familiar_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: true
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      cuentas_servicio: {
        Row: {
          activo: boolean
          alias: string | null
          concepto_id: string
          created_at: string
          id: string
          identificador_nombre: string | null
          identificador_valor: string
          tipo_identificador_id: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          alias?: string | null
          concepto_id: string
          created_at?: string
          id?: string
          identificador_nombre?: string | null
          identificador_valor: string
          tipo_identificador_id?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          alias?: string | null
          concepto_id?: string
          created_at?: string
          id?: string
          identificador_nombre?: string | null
          identificador_valor?: string
          tipo_identificador_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cuentas_servicio_concepto_id_fkey"
            columns: ["concepto_id"]
            isOneToOne: true
            referencedRelation: "conceptos_pago"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cuentas_servicio_tipo_identificador_id_fkey"
            columns: ["tipo_identificador_id"]
            isOneToOne: false
            referencedRelation: "tipos_identificador_proveedor"
            referencedColumns: ["id"]
          },
        ]
      }
      cuotas: {
        Row: {
          created_at: string
          destino: Database["public"]["Enums"]["destino_aporte"]
          estado: Database["public"]["Enums"]["estado_cuota"]
          familia_id: string
          id: string
          miembro_id: string
          monto_asignado: number
          monto_pagado: number
          nombre_miembro: string
          receptor_miembro_id: string | null
          recibo_id: string
          saldo_pendiente: number | null
          updated_at: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          destino?: Database["public"]["Enums"]["destino_aporte"]
          estado?: Database["public"]["Enums"]["estado_cuota"]
          familia_id: string
          id?: string
          miembro_id: string
          monto_asignado: number
          monto_pagado?: number
          nombre_miembro: string
          receptor_miembro_id?: string | null
          recibo_id: string
          saldo_pendiente?: number | null
          updated_at?: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          destino?: Database["public"]["Enums"]["destino_aporte"]
          estado?: Database["public"]["Enums"]["estado_cuota"]
          familia_id?: string
          id?: string
          miembro_id?: string
          monto_asignado?: number
          monto_pagado?: number
          nombre_miembro?: string
          receptor_miembro_id?: string | null
          recibo_id?: string
          saldo_pendiente?: number | null
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cuotas_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cuotas_miembro_id_fkey"
            columns: ["miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cuotas_receptor_miembro_id_fkey"
            columns: ["receptor_miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cuotas_recibo_id_fkey"
            columns: ["recibo_id"]
            isOneToOne: false
            referencedRelation: "recibos"
            referencedColumns: ["id"]
          },
        ]
      }
      eventos_financieros: {
        Row: {
          created_at: string
          detalle: Json
          entidad: string
          entidad_id: string | null
          evento: string
          familia_id: string
          id: number
          usuario_id: string | null
        }
        Insert: {
          created_at?: string
          detalle?: Json
          entidad: string
          entidad_id?: string | null
          evento: string
          familia_id: string
          id?: never
          usuario_id?: string | null
        }
        Update: {
          created_at?: string
          detalle?: Json
          entidad?: string
          entidad_id?: string | null
          evento?: string
          familia_id?: string
          id?: never
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "eventos_financieros_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      familias: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          id: string
          moneda: string
          nombre: string
          updated_at: string
          zona_horaria: string
        }
        Insert: {
          activo?: boolean
          creado_por: string
          created_at?: string
          id?: string
          moneda?: string
          nombre: string
          updated_at?: string
          zona_horaria?: string
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          id?: string
          moneda?: string
          nombre?: string
          updated_at?: string
          zona_horaria?: string
        }
        Relationships: []
      }
      invitaciones: {
        Row: {
          aceptada_at: string | null
          creado_por: string
          created_at: string
          email: string
          estado: Database["public"]["Enums"]["estado_invitacion"]
          expira_at: string
          familia_id: string
          id: string
          nombre: string | null
          rol: Database["public"]["Enums"]["rol_familia"]
          token_hash: string
        }
        Insert: {
          aceptada_at?: string | null
          creado_por: string
          created_at?: string
          email: string
          estado?: Database["public"]["Enums"]["estado_invitacion"]
          expira_at: string
          familia_id: string
          id?: string
          nombre?: string | null
          rol?: Database["public"]["Enums"]["rol_familia"]
          token_hash: string
        }
        Update: {
          aceptada_at?: string | null
          creado_por?: string
          created_at?: string
          email?: string
          estado?: Database["public"]["Enums"]["estado_invitacion"]
          expira_at?: string
          familia_id?: string
          id?: string
          nombre?: string | null
          rol?: Database["public"]["Enums"]["rol_familia"]
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitaciones_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      miembros_familia: {
        Row: {
          estado: Database["public"]["Enums"]["estado_miembro"]
          familia_id: string
          id: string
          joined_at: string
          rol: Database["public"]["Enums"]["rol_familia"]
          usuario_id: string
        }
        Insert: {
          estado?: Database["public"]["Enums"]["estado_miembro"]
          familia_id: string
          id?: string
          joined_at?: string
          rol?: Database["public"]["Enums"]["rol_familia"]
          usuario_id: string
        }
        Update: {
          estado?: Database["public"]["Enums"]["estado_miembro"]
          familia_id?: string
          id?: string
          joined_at?: string
          rol?: Database["public"]["Enums"]["rol_familia"]
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "miembros_familia_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      pagos_proveedor: {
        Row: {
          anulacion_motivo: string | null
          anulado_at: string | null
          anulado_por: string | null
          creado_por: string | null
          created_at: string
          estado: Database["public"]["Enums"]["estado_pago_proveedor"]
          familia_id: string
          fecha_pago: string
          id: string
          monto: number
          nota: string | null
          origen: Database["public"]["Enums"]["origen_pago_proveedor"]
          pagador_miembro_id: string | null
          pagador_nombre_snapshot: string | null
          recibo_id: string
          referencia: string | null
        }
        Insert: {
          anulacion_motivo?: string | null
          anulado_at?: string | null
          anulado_por?: string | null
          creado_por?: string | null
          created_at?: string
          estado?: Database["public"]["Enums"]["estado_pago_proveedor"]
          familia_id: string
          fecha_pago: string
          id?: string
          monto: number
          nota?: string | null
          origen: Database["public"]["Enums"]["origen_pago_proveedor"]
          pagador_miembro_id?: string | null
          pagador_nombre_snapshot?: string | null
          recibo_id: string
          referencia?: string | null
        }
        Update: {
          anulacion_motivo?: string | null
          anulado_at?: string | null
          anulado_por?: string | null
          creado_por?: string | null
          created_at?: string
          estado?: Database["public"]["Enums"]["estado_pago_proveedor"]
          familia_id?: string
          fecha_pago?: string
          id?: string
          monto?: number
          nota?: string | null
          origen?: Database["public"]["Enums"]["origen_pago_proveedor"]
          pagador_miembro_id?: string | null
          pagador_nombre_snapshot?: string | null
          recibo_id?: string
          referencia?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pagos_proveedor_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pagos_proveedor_pagador_miembro_id_fkey"
            columns: ["pagador_miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pagos_proveedor_recibo_id_fkey"
            columns: ["recibo_id"]
            isOneToOne: false
            referencedRelation: "recibos"
            referencedColumns: ["id"]
          },
        ]
      }
      perfiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          id: string
          nombre: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          id: string
          nombre?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          id?: string
          nombre?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      periodos: {
        Row: {
          anio: number
          cierre_tipo: Database["public"]["Enums"]["tipo_cierre_periodo"] | null
          completado_at: string | null
          completado_por: string | null
          created_at: string
          estado: Database["public"]["Enums"]["estado_periodo"]
          familia_id: string
          id: string
          mes: number
          motivo_cierre: string | null
        }
        Insert: {
          anio: number
          cierre_tipo?:
            | Database["public"]["Enums"]["tipo_cierre_periodo"]
            | null
          completado_at?: string | null
          completado_por?: string | null
          created_at?: string
          estado?: Database["public"]["Enums"]["estado_periodo"]
          familia_id: string
          id?: string
          mes: number
          motivo_cierre?: string | null
        }
        Update: {
          anio?: number
          cierre_tipo?:
            | Database["public"]["Enums"]["tipo_cierre_periodo"]
            | null
          completado_at?: string | null
          completado_por?: string | null
          created_at?: string
          estado?: Database["public"]["Enums"]["estado_periodo"]
          familia_id?: string
          id?: string
          mes?: number
          motivo_cierre?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "periodos_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      plantillas_servicio: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          descripcion: string | null
          frecuencia_recomendada: Database["public"]["Enums"]["frecuencia_concepto"]
          icono: string
          id: string
          metodo_obtencion_recomendado: Database["public"]["Enums"]["metodo_obtencion_monto"]
          nombre: string
          orden: number
          tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
          tipo_vencimiento_recomendado: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          descripcion?: string | null
          frecuencia_recomendada?: Database["public"]["Enums"]["frecuencia_concepto"]
          icono: string
          id?: string
          metodo_obtencion_recomendado?: Database["public"]["Enums"]["metodo_obtencion_monto"]
          nombre: string
          orden?: number
          tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
          tipo_vencimiento_recomendado?: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          descripcion?: string | null
          frecuencia_recomendada?: Database["public"]["Enums"]["frecuencia_concepto"]
          icono?: string
          id?: string
          metodo_obtencion_recomendado?: Database["public"]["Enums"]["metodo_obtencion_monto"]
          nombre?: string
          orden?: number
          tipo_servicio?: Database["public"]["Enums"]["tipo_servicio"]
          tipo_vencimiento_recomendado?: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
        }
        Relationships: []
      }
      proveedores: {
        Row: {
          activo: boolean
          codigo: string | null
          created_at: string
          es_sistema: boolean
          estado_integracion: Database["public"]["Enums"]["estado_integracion_proveedor"]
          familia_id: string | null
          id: string
          nombre: string
          tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          codigo?: string | null
          created_at?: string
          es_sistema?: boolean
          estado_integracion?: Database["public"]["Enums"]["estado_integracion_proveedor"]
          familia_id?: string | null
          id?: string
          nombre: string
          tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          codigo?: string | null
          created_at?: string
          es_sistema?: boolean
          estado_integracion?: Database["public"]["Enums"]["estado_integracion_proveedor"]
          familia_id?: string | null
          id?: string
          nombre?: string
          tipo_servicio?: Database["public"]["Enums"]["tipo_servicio"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "proveedores_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
        ]
      }
      recibo_ajustes: {
        Row: {
          anulacion_motivo: string | null
          anulado_at: string | null
          anulado_por: string | null
          creado_por: string | null
          created_at: string
          delta: number
          estado: Database["public"]["Enums"]["estado_ajuste_recibo"]
          familia_id: string
          id: string
          monto_anterior: number
          monto_nuevo: number
          motivo: string
          recibo_id: string
        }
        Insert: {
          anulacion_motivo?: string | null
          anulado_at?: string | null
          anulado_por?: string | null
          creado_por?: string | null
          created_at?: string
          delta: number
          estado?: Database["public"]["Enums"]["estado_ajuste_recibo"]
          familia_id: string
          id?: string
          monto_anterior: number
          monto_nuevo: number
          motivo: string
          recibo_id: string
        }
        Update: {
          anulacion_motivo?: string | null
          anulado_at?: string | null
          anulado_por?: string | null
          creado_por?: string | null
          created_at?: string
          delta?: number
          estado?: Database["public"]["Enums"]["estado_ajuste_recibo"]
          familia_id?: string
          id?: string
          monto_anterior?: number
          monto_nuevo?: number
          motivo?: string
          recibo_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recibo_ajustes_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recibo_ajustes_recibo_id_fkey"
            columns: ["recibo_id"]
            isOneToOne: false
            referencedRelation: "recibos"
            referencedColumns: ["id"]
          },
        ]
      }
      recibo_cuentas_snapshot: {
        Row: {
          alias: string | null
          created_at: string
          id: string
          identificador_nombre: string
          identificador_valor: string
          recibo_id: string
        }
        Insert: {
          alias?: string | null
          created_at?: string
          id?: string
          identificador_nombre: string
          identificador_valor: string
          recibo_id: string
        }
        Update: {
          alias?: string | null
          created_at?: string
          id?: string
          identificador_nombre?: string
          identificador_valor?: string
          recibo_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recibo_cuentas_snapshot_recibo_id_fkey"
            columns: ["recibo_id"]
            isOneToOne: true
            referencedRelation: "recibos"
            referencedColumns: ["id"]
          },
        ]
      }
      recibo_participantes_snapshot: {
        Row: {
          created_at: string
          id: string
          miembro_id: string
          modalidad: Database["public"]["Enums"]["modalidad_participante_concepto"]
          nombre_miembro: string
          orden: number
          recibo_id: string
          usuario_id: string
          valor: number | null
        }
        Insert: {
          created_at?: string
          id?: string
          miembro_id: string
          modalidad: Database["public"]["Enums"]["modalidad_participante_concepto"]
          nombre_miembro: string
          orden: number
          recibo_id: string
          usuario_id: string
          valor?: number | null
        }
        Update: {
          created_at?: string
          id?: string
          miembro_id?: string
          modalidad?: Database["public"]["Enums"]["modalidad_participante_concepto"]
          nombre_miembro?: string
          orden?: number
          recibo_id?: string
          usuario_id?: string
          valor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "recibo_participantes_snapshot_miembro_id_fkey"
            columns: ["miembro_id"]
            isOneToOne: false
            referencedRelation: "miembros_familia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recibo_participantes_snapshot_recibo_id_fkey"
            columns: ["recibo_id"]
            isOneToOne: false
            referencedRelation: "recibos"
            referencedColumns: ["id"]
          },
        ]
      }
      recibos: {
        Row: {
          categoria_nombre: string
          concepto_id: string
          created_at: string
          dias_anticipacion_aporte: number
          distribucion_ajustada: boolean
          distribucion_ajuste_motivo: string | null
          estado: Database["public"]["Enums"]["estado_recibo"]
          estado_recaudacion: Database["public"]["Enums"]["estado_recaudacion"]
          familia_id: string
          fecha_limite_aporte: string | null
          fecha_vencimiento: string | null
          frecuencia: Database["public"]["Enums"]["frecuencia_concepto"]
          id: string
          metodo_obtencion: Database["public"]["Enums"]["metodo_obtencion_monto"]
          monto_ajustes: number
          monto_base: number | null
          monto_confirmado_at: string | null
          monto_total: number | null
          nombre_concepto: string
          periodo_id: string
          proveedor_nombre: string
          reparto_resto:
            | Database["public"]["Enums"]["tipo_reparto_resto"]
            | null
          tipo_distribucion: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
          tipo_vencimiento: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
          updated_at: string
        }
        Insert: {
          categoria_nombre: string
          concepto_id: string
          created_at?: string
          dias_anticipacion_aporte: number
          distribucion_ajustada?: boolean
          distribucion_ajuste_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_recibo"]
          estado_recaudacion?: Database["public"]["Enums"]["estado_recaudacion"]
          familia_id: string
          fecha_limite_aporte?: string | null
          fecha_vencimiento?: string | null
          frecuencia: Database["public"]["Enums"]["frecuencia_concepto"]
          id?: string
          metodo_obtencion: Database["public"]["Enums"]["metodo_obtencion_monto"]
          monto_ajustes?: number
          monto_base?: number | null
          monto_confirmado_at?: string | null
          monto_total?: number | null
          nombre_concepto: string
          periodo_id: string
          proveedor_nombre: string
          reparto_resto?:
            | Database["public"]["Enums"]["tipo_reparto_resto"]
            | null
          tipo_distribucion: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
          tipo_vencimiento: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
          updated_at?: string
        }
        Update: {
          categoria_nombre?: string
          concepto_id?: string
          created_at?: string
          dias_anticipacion_aporte?: number
          distribucion_ajustada?: boolean
          distribucion_ajuste_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_recibo"]
          estado_recaudacion?: Database["public"]["Enums"]["estado_recaudacion"]
          familia_id?: string
          fecha_limite_aporte?: string | null
          fecha_vencimiento?: string | null
          frecuencia?: Database["public"]["Enums"]["frecuencia_concepto"]
          id?: string
          metodo_obtencion?: Database["public"]["Enums"]["metodo_obtencion_monto"]
          monto_ajustes?: number
          monto_base?: number | null
          monto_confirmado_at?: string | null
          monto_total?: number | null
          nombre_concepto?: string
          periodo_id?: string
          proveedor_nombre?: string
          reparto_resto?:
            | Database["public"]["Enums"]["tipo_reparto_resto"]
            | null
          tipo_distribucion?: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          tipo_servicio?: Database["public"]["Enums"]["tipo_servicio"]
          tipo_vencimiento?: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "recibos_concepto_id_fkey"
            columns: ["concepto_id"]
            isOneToOne: false
            referencedRelation: "conceptos_pago"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recibos_familia_id_fkey"
            columns: ["familia_id"]
            isOneToOne: false
            referencedRelation: "familias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recibos_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos"
            referencedColumns: ["id"]
          },
        ]
      }
      tipos_identificador_proveedor: {
        Row: {
          activo: boolean
          ayuda: string | null
          codigo: string
          created_at: string
          id: string
          nombre: string
          orden: number
          proveedor_id: string
        }
        Insert: {
          activo?: boolean
          ayuda?: string | null
          codigo: string
          created_at?: string
          id?: string
          nombre: string
          orden?: number
          proveedor_id: string
        }
        Update: {
          activo?: boolean
          ayuda?: string | null
          codigo?: string
          created_at?: string
          id?: string
          nombre?: string
          orden?: number
          proveedor_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tipos_identificador_proveedor_proveedor_id_fkey"
            columns: ["proveedor_id"]
            isOneToOne: false
            referencedRelation: "proveedores"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      actualizar_vencimiento_recibo: {
        Args: { p_fecha_vencimiento: string; p_recibo_id: string }
        Returns: undefined
      }
      ajustar_cuotas_recibo: {
        Args: { p_cuotas: Json; p_motivo: string; p_recibo_id: string }
        Returns: undefined
      }
      anular_aporte: {
        Args: { p_aporte_id: string; p_motivo: string }
        Returns: undefined
      }
      anular_pago_proveedor: {
        Args: { p_motivo: string; p_pago_id: string }
        Returns: undefined
      }
      anular_recibo: {
        Args: { p_motivo: string; p_recibo_id: string }
        Returns: undefined
      }
      cambiar_estado_concepto: {
        Args: { p_activo: boolean; p_concepto_id: string }
        Returns: undefined
      }
      cambiar_estado_proveedor_personalizado: {
        Args: { p_activo: boolean; p_proveedor_id: string }
        Returns: undefined
      }
      cerrar_periodo: {
        Args: { p_motivo?: string; p_periodo_id: string }
        Returns: undefined
      }
      confirmar_monto_recibo: {
        Args: {
          p_fecha_vencimiento: string
          p_monto: number
          p_recibo_id: string
        }
        Returns: undefined
      }
      corregir_monto_recibo: {
        Args: {
          p_fecha_vencimiento?: string
          p_motivo: string
          p_nuevo_monto: number
          p_recibo_id: string
        }
        Returns: undefined
      }
      crear_familia_inicial: { Args: { p_nombre: string }; Returns: string }
      crear_proveedor_personalizado: {
        Args: {
          p_familia_id: string
          p_nombre: string
          p_tipo_servicio: Database["public"]["Enums"]["tipo_servicio"]
        }
        Returns: string
      }
      guardar_concepto_servicio: {
        Args: {
          p_categoria_id: string
          p_concepto_id: string
          p_cuenta: Json
          p_dia_vencimiento: number
          p_fallback_manual: boolean
          p_familia_id: string
          p_frecuencia: Database["public"]["Enums"]["frecuencia_concepto"]
          p_metodo_obtencion: Database["public"]["Enums"]["metodo_obtencion_monto"]
          p_monto_fijo: number
          p_nombre: string
          p_participantes: Json
          p_plantilla_id: string
          p_proveedor_id: string
          p_reparto_resto: Database["public"]["Enums"]["tipo_reparto_resto"]
          p_tipo_distribucion: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          p_tipo_vencimiento: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
        }
        Returns: string
      }
      guardar_concepto_servicio_fase6: {
        Args: {
          p_categoria_id: string
          p_concepto_id: string
          p_cuenta: Json
          p_dia_vencimiento: number
          p_dias_anticipacion_aporte: number
          p_fallback_manual: boolean
          p_familia_id: string
          p_fecha_inicio_generacion: string
          p_frecuencia: Database["public"]["Enums"]["frecuencia_concepto"]
          p_metodo_obtencion: Database["public"]["Enums"]["metodo_obtencion_monto"]
          p_monto_fijo: number
          p_nombre: string
          p_participantes: Json
          p_plantilla_id: string
          p_proveedor_id: string
          p_reparto_resto: Database["public"]["Enums"]["tipo_reparto_resto"]
          p_tipo_distribucion: Database["public"]["Enums"]["tipo_distribucion_concepto"]
          p_tipo_vencimiento: Database["public"]["Enums"]["tipo_vencimiento_concepto"]
        }
        Returns: string
      }
      registrar_aporte: {
        Args: {
          p_cuota_id: string
          p_metodo: Database["public"]["Enums"]["metodo_pago_familiar"]
          p_monto: number
          p_nota?: string
          p_referencia?: string
        }
        Returns: string
      }
      registrar_pago_proveedor: {
        Args: {
          p_fecha_pago: string
          p_monto: number
          p_nota?: string
          p_origen: Database["public"]["Enums"]["origen_pago_proveedor"]
          p_pagador_miembro_id: string
          p_recibo_id: string
          p_referencia?: string
        }
        Returns: string
      }
      sincronizar_periodo_actual: {
        Args: { p_familia_id: string }
        Returns: number
      }
      validar_aporte: {
        Args: { p_aporte_id: string; p_aprobar: boolean; p_motivo?: string }
        Returns: undefined
      }
    }
    Enums: {
      destino_aporte: "FONDO_FAMILIAR" | "INTEGRANTE"
      estado_ajuste_recibo: "APLICADO" | "ANULADO"
      estado_aporte: "POR_VALIDAR" | "CONFIRMADO" | "RECHAZADO" | "ANULADO"
      estado_cuota:
        | "PENDIENTE"
        | "PARCIAL"
        | "POR_VALIDAR"
        | "PAGADA"
        | "RECHAZADA"
        | "ANULADA"
      estado_integracion_proveedor: "NO_DISPONIBLE" | "PREPARADO" | "DISPONIBLE"
      estado_invitacion: "PENDIENTE" | "ACEPTADA" | "EXPIRADA" | "REVOCADA"
      estado_miembro: "ACTIVO" | "INACTIVO"
      estado_pago_proveedor: "CONFIRMADO" | "ANULADO"
      estado_periodo: "ABIERTO" | "COMPLETADO"
      estado_recaudacion: "PENDIENTE" | "PARCIAL" | "COMPLETA"
      estado_recibo:
        | "ESPERANDO_MONTO"
        | "PENDIENTE"
        | "PAGADO"
        | "VENCIDO"
        | "ANULADO"
        | "REQUIERE_REVISION"
      frecuencia_concepto: "MENSUAL" | "ANUAL" | "UNICA"
      metodo_obtencion_monto: "MANUAL" | "FIJO" | "AUTOMATICO"
      metodo_pago_familiar: "YAPE" | "TRANSFERENCIA" | "EFECTIVO" | "OTRO"
      modalidad_participante_concepto:
        | "IGUAL"
        | "PORCENTAJE"
        | "MONTO_FIJO"
        | "RESTO_IGUAL"
        | "RESTO_PORCENTAJE"
      origen_pago_proveedor: "FONDO_FAMILIAR" | "ADELANTO_INTEGRANTE"
      rol_familia: "ADMINISTRADOR" | "INTEGRANTE"
      tipo_aporte: "APORTE_FAMILIAR" | "REEMBOLSO" | "COBERTURA_ADELANTO"
      tipo_cierre_periodo: "AUTOMATICO" | "MANUAL"
      tipo_distribucion_concepto:
        | "IGUAL"
        | "PORCENTAJE"
        | "MONTO_FIJO"
        | "MIXTA"
      tipo_reparto_resto: "IGUAL" | "PORCENTAJE"
      tipo_servicio: "AGUA" | "LUZ" | "INTERNET" | "GAS" | "OTRO"
      tipo_vencimiento_concepto: "DIA_FIJO" | "VARIABLE" | "PROVEEDOR"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      destino_aporte: ["FONDO_FAMILIAR", "INTEGRANTE"],
      estado_ajuste_recibo: ["APLICADO", "ANULADO"],
      estado_aporte: ["POR_VALIDAR", "CONFIRMADO", "RECHAZADO", "ANULADO"],
      estado_cuota: [
        "PENDIENTE",
        "PARCIAL",
        "POR_VALIDAR",
        "PAGADA",
        "RECHAZADA",
        "ANULADA",
      ],
      estado_integracion_proveedor: [
        "NO_DISPONIBLE",
        "PREPARADO",
        "DISPONIBLE",
      ],
      estado_invitacion: ["PENDIENTE", "ACEPTADA", "EXPIRADA", "REVOCADA"],
      estado_miembro: ["ACTIVO", "INACTIVO"],
      estado_pago_proveedor: ["CONFIRMADO", "ANULADO"],
      estado_periodo: ["ABIERTO", "COMPLETADO"],
      estado_recaudacion: ["PENDIENTE", "PARCIAL", "COMPLETA"],
      estado_recibo: [
        "ESPERANDO_MONTO",
        "PENDIENTE",
        "PAGADO",
        "VENCIDO",
        "ANULADO",
        "REQUIERE_REVISION",
      ],
      frecuencia_concepto: ["MENSUAL", "ANUAL", "UNICA"],
      metodo_obtencion_monto: ["MANUAL", "FIJO", "AUTOMATICO"],
      metodo_pago_familiar: ["YAPE", "TRANSFERENCIA", "EFECTIVO", "OTRO"],
      modalidad_participante_concepto: [
        "IGUAL",
        "PORCENTAJE",
        "MONTO_FIJO",
        "RESTO_IGUAL",
        "RESTO_PORCENTAJE",
      ],
      origen_pago_proveedor: ["FONDO_FAMILIAR", "ADELANTO_INTEGRANTE"],
      rol_familia: ["ADMINISTRADOR", "INTEGRANTE"],
      tipo_aporte: ["APORTE_FAMILIAR", "REEMBOLSO", "COBERTURA_ADELANTO"],
      tipo_cierre_periodo: ["AUTOMATICO", "MANUAL"],
      tipo_distribucion_concepto: [
        "IGUAL",
        "PORCENTAJE",
        "MONTO_FIJO",
        "MIXTA",
      ],
      tipo_reparto_resto: ["IGUAL", "PORCENTAJE"],
      tipo_servicio: ["AGUA", "LUZ", "INTERNET", "GAS", "OTRO"],
      tipo_vencimiento_concepto: ["DIA_FIJO", "VARIABLE", "PROVEEDOR"],
    },
  },
} as const
