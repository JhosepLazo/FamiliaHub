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
          fallback_manual: boolean
          familia_id: string
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
          fallback_manual?: boolean
          familia_id: string
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
          fallback_manual?: boolean
          familia_id?: string
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
          completado_at: string | null
          created_at: string
          estado: Database["public"]["Enums"]["estado_periodo"]
          familia_id: string
          id: string
          mes: number
        }
        Insert: {
          anio: number
          completado_at?: string | null
          created_at?: string
          estado?: Database["public"]["Enums"]["estado_periodo"]
          familia_id: string
          id?: string
          mes: number
        }
        Update: {
          anio?: number
          completado_at?: string | null
          created_at?: string
          estado?: Database["public"]["Enums"]["estado_periodo"]
          familia_id?: string
          id?: string
          mes?: number
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
      cambiar_estado_concepto: {
        Args: { p_activo: boolean; p_concepto_id: string }
        Returns: undefined
      }
      cambiar_estado_proveedor_personalizado: {
        Args: { p_activo: boolean; p_proveedor_id: string }
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
    }
    Enums: {
      estado_integracion_proveedor: "NO_DISPONIBLE" | "PREPARADO" | "DISPONIBLE"
      estado_invitacion: "PENDIENTE" | "ACEPTADA" | "EXPIRADA" | "REVOCADA"
      estado_miembro: "ACTIVO" | "INACTIVO"
      estado_periodo: "ABIERTO" | "COMPLETADO"
      frecuencia_concepto: "MENSUAL" | "ANUAL" | "UNICA"
      metodo_obtencion_monto: "MANUAL" | "FIJO" | "AUTOMATICO"
      metodo_pago_familiar: "YAPE" | "TRANSFERENCIA" | "EFECTIVO" | "OTRO"
      modalidad_participante_concepto:
        | "IGUAL"
        | "PORCENTAJE"
        | "MONTO_FIJO"
        | "RESTO_IGUAL"
        | "RESTO_PORCENTAJE"
      rol_familia: "ADMINISTRADOR" | "INTEGRANTE"
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
      estado_integracion_proveedor: [
        "NO_DISPONIBLE",
        "PREPARADO",
        "DISPONIBLE",
      ],
      estado_invitacion: ["PENDIENTE", "ACEPTADA", "EXPIRADA", "REVOCADA"],
      estado_miembro: ["ACTIVO", "INACTIVO"],
      estado_periodo: ["ABIERTO", "COMPLETADO"],
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
      rol_familia: ["ADMINISTRADOR", "INTEGRANTE"],
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
