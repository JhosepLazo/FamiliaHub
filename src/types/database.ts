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
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      crear_familia_inicial: { Args: { p_nombre: string }; Returns: string }
    }
    Enums: {
      estado_invitacion: "PENDIENTE" | "ACEPTADA" | "EXPIRADA" | "REVOCADA"
      estado_miembro: "ACTIVO" | "INACTIVO"
      estado_periodo: "ABIERTO" | "COMPLETADO"
      metodo_pago_familiar: "YAPE" | "TRANSFERENCIA" | "EFECTIVO" | "OTRO"
      rol_familia: "ADMINISTRADOR" | "INTEGRANTE"
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
      estado_invitacion: ["PENDIENTE", "ACEPTADA", "EXPIRADA", "REVOCADA"],
      estado_miembro: ["ACTIVO", "INACTIVO"],
      estado_periodo: ["ABIERTO", "COMPLETADO"],
      metodo_pago_familiar: ["YAPE", "TRANSFERENCIA", "EFECTIVO", "OTRO"],
      rol_familia: ["ADMINISTRADOR", "INTEGRANTE"],
    },
  },
} as const
