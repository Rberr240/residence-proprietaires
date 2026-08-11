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
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      access_codes: {
        Row: {
          active: boolean
          apartment_id: string
          code_hash: string
          created_at: string
          expires_at: string | null
          id: string
          used_at: string | null
        }
        Insert: {
          active?: boolean
          apartment_id: string
          code_hash: string
          created_at?: string
          expires_at?: string | null
          id?: string
          used_at?: string | null
        }
        Update: {
          active?: boolean
          apartment_id?: string
          code_hash?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "access_codes_apartment_id_fkey"
            columns: ["apartment_id"]
            isOneToOne: false
            referencedRelation: "apartments"
            referencedColumns: ["id"]
          },
        ]
      }
      apartments: {
        Row: {
          apartment_number: string
          building_id: string
          created_at: string
          floor: number | null
          id: string
        }
        Insert: {
          apartment_number: string
          building_id: string
          created_at?: string
          floor?: number | null
          id?: string
        }
        Update: {
          apartment_number?: string
          building_id?: string
          created_at?: string
          floor?: number | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "apartments_building_id_fkey"
            columns: ["building_id"]
            isOneToOne: false
            referencedRelation: "buildings"
            referencedColumns: ["id"]
          },
        ]
      }
      buildings: {
        Row: {
          active: boolean
          apartment_count: number | null
          code: string
          created_at: string
          id: string
          name: string
          type: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          apartment_count?: number | null
          code: string
          created_at?: string
          id?: string
          name: string
          type: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          apartment_count?: number | null
          code?: string
          created_at?: string
          id?: string
          name?: string
          type?: string
          updated_at?: string
        }
        Relationships: []
      }
      meeting_responses: {
        Row: {
          attendance: string | null
          availability: string[]
          created_at: string
          id: string
          meeting_id: string
          owner_id: string
          subject: string | null
          updated_at: string
        }
        Insert: {
          attendance?: string | null
          availability?: string[]
          created_at?: string
          id?: string
          meeting_id: string
          owner_id: string
          subject?: string | null
          updated_at?: string
        }
        Update: {
          attendance?: string | null
          availability?: string[]
          created_at?: string
          id?: string
          meeting_id?: string
          owner_id?: string
          subject?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meeting_responses_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_responses_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "owners"
            referencedColumns: ["id"]
          },
        ]
      }
      meetings: {
        Row: {
          created_at: string
          description: string | null
          id: string
          location: string | null
          meeting_date: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          location?: string | null
          meeting_date?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          location?: string | null
          meeting_date?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      owner_account_units: {
        Row: {
          apartment_number: string
          building_code: string
          created_at: string
          id: string
          is_primary: boolean
          owner_account_id: string
          submission_id: string
        }
        Insert: {
          apartment_number: string
          building_code: string
          created_at?: string
          id?: string
          is_primary?: boolean
          owner_account_id: string
          submission_id: string
        }
        Update: {
          apartment_number?: string
          building_code?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          owner_account_id?: string
          submission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "owner_account_units_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "owner_account_units_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: true
            referencedRelation: "owner_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      owner_accounts: {
        Row: {
          activated_at: string | null
          auth_user_id: string | null
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string
          phone: string
          phone_e164: string | null
          status: string
          whatsapp: string | null
        }
        Insert: {
          activated_at?: string | null
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name: string
          phone: string
          phone_e164?: string | null
          status?: string
          whatsapp?: string | null
        }
        Update: {
          activated_at?: string | null
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string
          phone?: string
          phone_e164?: string | null
          status?: string
          whatsapp?: string | null
        }
        Relationships: []
      }
      owner_activation_codes: {
        Row: {
          code_hash: string
          created_at: string
          expires_at: string
          id: string
          owner_account_id: string
          revoked_at: string | null
          used_at: string | null
        }
        Insert: {
          code_hash: string
          created_at?: string
          expires_at: string
          id?: string
          owner_account_id: string
          revoked_at?: string | null
          used_at?: string | null
        }
        Update: {
          code_hash?: string
          created_at?: string
          expires_at?: string
          id?: string
          owner_account_id?: string
          revoked_at?: string | null
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "owner_activation_codes_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      owner_submissions: {
        Row: {
          apartment_number: string
          attendance: string | null
          availability: string[]
          building_code: string
          cin: string | null
          consent: boolean
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string
          phone: string
          status: string
          subject: string | null
          whatsapp: string | null
        }
        Insert: {
          apartment_number: string
          attendance?: string | null
          availability?: string[]
          building_code: string
          cin?: string | null
          consent: boolean
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name: string
          phone: string
          status?: string
          subject?: string | null
          whatsapp?: string | null
        }
        Update: {
          apartment_number?: string
          attendance?: string | null
          availability?: string[]
          building_code?: string
          cin?: string | null
          consent?: boolean
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string
          phone?: string
          status?: string
          subject?: string | null
          whatsapp?: string | null
        }
        Relationships: []
      }
      owners: {
        Row: {
          apartment_id: string
          consent: boolean
          consent_at: string | null
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string
          phone: string
          updated_at: string
          verified: boolean
          whatsapp: string | null
        }
        Insert: {
          apartment_id: string
          consent?: boolean
          consent_at?: string | null
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name: string
          phone: string
          updated_at?: string
          verified?: boolean
          whatsapp?: string | null
        }
        Update: {
          apartment_id?: string
          consent?: boolean
          consent_at?: string | null
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string
          phone?: string
          updated_at?: string
          verified?: boolean
          whatsapp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "owners_apartment_id_fkey"
            columns: ["apartment_id"]
            isOneToOne: false
            referencedRelation: "apartments"
            referencedColumns: ["id"]
          },
        ]
      }
      registration_sessions: {
        Row: {
          access_code_id: string
          apartment_id: string
          consumed_at: string | null
          created_at: string
          expires_at: string
          id: string
          token_hash: string
        }
        Insert: {
          access_code_id: string
          apartment_id: string
          consumed_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          token_hash: string
        }
        Update: {
          access_code_id?: string
          apartment_id?: string
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "registration_sessions_access_code_id_fkey"
            columns: ["access_code_id"]
            isOneToOne: false
            referencedRelation: "access_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "registration_sessions_apartment_id_fkey"
            columns: ["apartment_id"]
            isOneToOne: false
            referencedRelation: "apartments"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      register_owner_with_session:
        | {
            Args: {
              p_consent?: boolean
              p_email?: string
              p_first_name: string
              p_last_name: string
              p_phone: string
              p_token_hash: string
              p_whatsapp?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_attendance: string
              p_availability: string[]
              p_consent: boolean
              p_email: string
              p_first_name: string
              p_last_name: string
              p_phone: string
              p_subject: string
              p_token_hash: string
              p_whatsapp: string
            }
            Returns: Json
          }
    }
    Enums: {
      [_ in never]: never
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
